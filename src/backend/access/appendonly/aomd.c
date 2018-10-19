/*-------------------------------------------------------------------------
 *
 * aomd.c
 *	  This code manages append only relations that reside on magnetic disk.
 *	  It serves the same general purpose as smgr/md.c however we introduce
 *    AO specific file access functions mainly because would like to bypass 
 *	  md.c's and bgwriter's fsyncing. AO relations also use a non constant
 *	  block number to file segment mapping unlike heap relations.
 *
 *	  As of now we still let md.c create and unlink AO relations for us. This
 *	  may need to change if inconsistencies arise.
 *
 * Portions Copyright (c) 2008, Greenplum Inc.
 * Portions Copyright (c) 2012-Present Pivotal Software, Inc.
 * Portions Copyright (c) 1996-2008, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	    src/backend/access/appendonly/aomd.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <access/aomd.h>

#include "access/aomd.h"
#include "access/appendonlytid.h"
#include "access/appendonlywriter.h"
#include "catalog/catalog.h"
#include "cdb/cdbappendonlystorage.h"
#include "cdb/cdbappendonlyxlog.h"
#include "common/relpath.h"
#include "utils/guc.h"

static bool
aoRelFileOperationCallback_unlink(const int segno, const aoRelfileOperation_t operation,
                                  const aoRelFileOperationData_t *user_data);
static bool
aoRelFileOperationCallback_copy_files(const int segno, const aoRelfileOperation_t operation,
                                      const aoRelFileOperationData_t *user_data);

int
AOSegmentFilePathNameLen(Relation rel)
{
	char		*basepath;
	int 		len;
		
	/* Get base path for this relation file */
	basepath = relpathbackend(rel->rd_node, rel->rd_backend, MAIN_FORKNUM);

	/*
	 * The basepath will be the RelFileNode number.  Optional part is dot "." plus 
	 * 6 digit segment file number.
	 */
	len = strlen(basepath) + 8;	// Generous.
	
	pfree(basepath);

	return len;
}

/*
 * Formats an Append Only relation file segment file name.
 *
 * The filepathname parameter assume sufficient space.
 */
void
FormatAOSegmentFileName(char *basepath,
						int segno,
						int col,
						int32 *fileSegNo,
						char *filepathname)
{
	int	pseudoSegNo;
	
	Assert(segno >= 0);
	Assert(segno <= AOTupleId_MaxSegmentFileNum);

	if (col < 0)
	{
		/*
		 * Row oriented Append-Only.
		 */
		pseudoSegNo = segno;		
	}
	else
	{
		/*
		 * Column oriented Append-only.
		 */
		pseudoSegNo = (col*AOTupleId_MultiplierSegmentFileNum) + segno;
	}
	
	*fileSegNo = pseudoSegNo;

	if (pseudoSegNo > 0)
	{
		sprintf(filepathname, "%s.%u", basepath, pseudoSegNo);
	}
	else
		strcpy(filepathname, basepath);
}

/*
 * Make an Append Only relation file segment file name.
 *
 * The filepathname parameter assume sufficient space.
 */
void
MakeAOSegmentFileName(Relation rel,
					  int segno,
					  int col,
					  int32 *fileSegNo,
					  char *filepathname)
{
	char	*basepath;
	int32   fileSegNoLocal;
	
	/* Get base path for this relation file */
	basepath = relpathbackend(rel->rd_node, rel->rd_backend, MAIN_FORKNUM);

	FormatAOSegmentFileName(basepath, segno, col, &fileSegNoLocal, filepathname);
	
	*fileSegNo = fileSegNoLocal;
	
	pfree(basepath);
}

/*
 * Open an Append Only relation file segment
 *
 * The fd module's PathNameOpenFile() is used to open the file, so the
 * the File* routines can be used to read, write, close, etc, the file.
 */
File
OpenAOSegmentFile(Relation rel, 
				  char *filepathname, 
				  int32	segmentFileNum,
				  int64	logicalEof)
{	
	char	   *dbPath;
	char		path[MAXPGPATH];
	int			fileFlags = O_RDWR | PG_BINARY;
	File		fd;

	dbPath = GetDatabasePath(rel->rd_node.dbNode, rel->rd_node.spcNode);

	if (segmentFileNum == 0)
		snprintf(path, MAXPGPATH, "%s/%u", dbPath, rel->rd_node.relNode);
	else
		snprintf(path, MAXPGPATH, "%s/%u.%u", dbPath, rel->rd_node.relNode, segmentFileNum);

	errno = 0;

	fd = PathNameOpenFile(path, fileFlags, 0600);
	if (fd < 0)
	{
		if (logicalEof == 0 && errno == ENOENT)
			return -1;

		ereport(ERROR,
				(errcode_for_file_access(),
				 errmsg("could not open Append-Only segment file \"%s\": %m",
						filepathname)));
	}
	pfree(dbPath);

	return fd;
}


/*
 * Close an Append Only relation file segment
 */
void
CloseAOSegmentFile(File fd)
{
	FileClose(fd);
}

/*
 * Truncate all bytes from offset to end of file.
 */
void
TruncateAOSegmentFile(File fd, Relation rel, int32 segFileNum, int64 offset)
{
	char *relname = RelationGetRelationName(rel);

	Assert(fd > 0);
	Assert(offset >= 0);

	/*
	 * Call the 'fd' module with a 64-bit length since AO segment files
	 * can be multi-gigabyte to the terabytes...
	 */
	if (FileTruncate(fd, offset) != 0)
		ereport(ERROR,
				(errmsg("\"%s\": failed to truncate data after eof: %m",
					    relname)));
	if (RelationNeedsWAL(rel))
		xlog_ao_truncate(rel->rd_node, segFileNum, offset);
}

/*
 * Delete All segment file extensions, in case it was an AO or AOCS
 * table. Ideally the logic works even for heap tables, but is only used
 * currently for AO and AOCS tables to avoid merge conflicts.
 *
 * There are different rules for the naming of the files, depending on
 * the type of table:
 *
 *   Heap Tables: contiguous extensions, no upper bound
 *   AO Tables: non contiguous extensions [.1 - .127]
 *   CO Tables: non contiguous extensions
 *          [  .1 - .127] for first column;  .0 reserved for utility and alter
 *          [.129 - .255] for second column; .128 reserved for utility and alter
 *          [.257 - .283] for third column;  .256 reserved for utility and alter
 *          etc
 *
 *  Algorithm is coded with the assumption for CO tables that for a given
 *  concurrency level, the relfiles exist OR stop existing for all columns thereafter.
 *  For instance, if .2 exists, then .(2 + 128N) MIGHT exist for N=1.  But if it does
 *  not exist for N=1, then it doesn't exist for N>=2.
 *
 *  1) Finds for which concurrency levels the table has files. This is
 *     calculated based off the first column. It performs 127
 *     (MAX_AOREL_CONCURRENCY) unlink().
 *  2) Iterates over a concurrency level, unlinking all files for each column.  It uses
 *     the above assumption to stop and proceed to the next concurrency level.
 */
void
mdunlink_ao(const char *path)
{
	int path_size = strlen(path);
	char *segpath = (char *) palloc(path_size + 12);
	char *segpath_suffix_position = segpath + path_size;
	aoRelFileOperationData_t ud;

	strncpy(segpath, path, path_size);

	ud.operation = MD_UNLINK;
	ud.data.md_unlink.segpath = segpath;
	ud.data.md_unlink.segpath_suffix_position = segpath_suffix_position;
	aoRelfileOperationExecute(aoRelFileOperationCallback_unlink, MD_UNLINK, &ud);

	pfree(segpath);
}

bool
aoRelFileOperationCallback_unlink(const int segno, const aoRelfileOperation_t operation,
		const aoRelFileOperationData_t *user_data) {

	char *segpath = user_data->data.md_unlink.segpath;
	char *segpath_suffix_position = user_data->data.md_unlink.segpath_suffix_position;

	sprintf(segpath_suffix_position, ".%u", segno);
	if (unlink(segpath) != 0)
	{
		/* ENOENT is expected after the end of the extensions */
		if (errno != ENOENT)
			ereport(WARNING,
					(errcode_for_file_access(),
							errmsg("could not remove file \"%s\": %m", segpath)));
		else
			return false;
	}

	return true;
}

static void
copy_file(char *srcsegpath, char *dstsegpath,
		  RelFileNode dst, int segfilenum, bool use_wal)
{
	File		srcFile;
	File		dstFile;
	int64		left;
	off_t		offset;
	char       *buffer = palloc(BLCKSZ);
	int dstflags;

	srcFile = PathNameOpenFile(srcsegpath, O_RDONLY | PG_BINARY, 0600);
	if (srcFile < 0)
		ereport(ERROR,
				(errcode_for_file_access(),
				 (errmsg("could not open file %s: %m", srcsegpath))));

	dstflags = O_WRONLY | O_EXCL | PG_BINARY;
	/*
	 * .0 relfilenode is expected to exist before calling this
	 * function. Caller calls RelationCreateStorage() which creates the base
	 * file for the relation. Hence use different flag for the same.
	 */
	if (segfilenum)
		dstflags |= O_CREAT;

	dstFile = PathNameOpenFile(dstsegpath, dstflags, 0600);
	if (dstFile < 0)
		ereport(ERROR,
				(errcode_for_file_access(),
				 (errmsg("could not create destination file %s: %m", dstsegpath))));

	left = FileSeek(srcFile, 0, SEEK_END);
	if (left < 0)
		ereport(ERROR,
				(errcode_for_file_access(),
				 (errmsg("could not seek to end of file %s: %m", srcsegpath))));

	if (FileSeek(srcFile, 0, SEEK_SET) < 0)
		ereport(ERROR,
				(errcode_for_file_access(),
				 (errmsg("could not seek to beginning of file %s: %m", srcsegpath))));

	offset = 0;
	while(left > 0)
	{
		int			len;

		CHECK_FOR_INTERRUPTS();

		len = Min(left, BLCKSZ);
		if (FileRead(srcFile, buffer, len) != len)
			ereport(ERROR,
					(errcode_for_file_access(),
					 errmsg("could not read %d bytes from file \"%s\": %m",
							len, srcsegpath)));

		if (FileWrite(dstFile, buffer, len) != len)
			ereport(ERROR,
					(errcode_for_file_access(),
					 errmsg("could not write %d bytes to file \"%s\": %m",
							len, dstsegpath)));

		if (use_wal)
			xlog_ao_insert(dst, segfilenum, offset, buffer, len);

		offset += len;
		left -= len;
	}

	if (FileSync(dstFile) != 0)
		ereport(ERROR,
				(errcode_for_file_access(),
				 errmsg("could not fsync file \"%s\": %m",
						dstsegpath)));
	FileClose(srcFile);
	FileClose(dstFile);
	pfree(buffer);
}

/*
 * Like copy_relation_data(), but for AO tables.
 *
 * Currently, AO tables don't have any extra forks.
 */
void
copy_append_only_data(RelFileNode src, RelFileNode dst,
        BackendId backendid, char relpersistence)
{
	char *srcpath;
	char *dstpath;
	bool use_wal;
	aoRelFileOperationData_t ud;
	/*
	 * We need to log the copied data in WAL iff WAL archiving/streaming is
	 * enabled AND it's a permanent relation.
	 */
	use_wal = XLogIsNeeded() && relpersistence == RELPERSISTENCE_PERMANENT;

	srcpath = relpathbackend(src, backendid, MAIN_FORKNUM);
	dstpath = relpathbackend(dst, backendid, MAIN_FORKNUM);

	copy_file(srcpath, dstpath, dst, 0, use_wal);

	ud.operation = COPY_FILES;
	ud.data.copy_files.srcpath = srcpath;
	ud.data.copy_files.dstpath = dstpath;
	ud.data.copy_files.dst = dst;
	ud.data.copy_files.useWal = use_wal;
	aoRelfileOperationExecute(aoRelFileOperationCallback_copy_files, COPY_FILES, &ud);
}

bool
aoRelFileOperationCallback_copy_files(const int segno, const aoRelfileOperation_t operation,
								  const aoRelFileOperationData_t *user_data)
{
	Assert(COPY_FILES == user_data->operation);
	Assert(COPY_FILES == operation);

	char srcsegpath[MAXPGPATH + 12];
	char dstsegpath[MAXPGPATH + 12];
	char *srcpath = user_data->data.copy_files.srcpath;
	char *dstpath = user_data->data.copy_files.dstpath;
	RelFileNode dst = user_data->data.copy_files.dst;
    bool use_wal = user_data->data.copy_files.useWal;

	sprintf(srcsegpath, "%s.%u", srcpath, segno);
	if (access(srcsegpath, F_OK) != 0)
	{
		/* ENOENT is expected after the end of the extensions */
		if (errno != ENOENT)
			ereport(ERROR,
					(errcode_for_file_access(),
							errmsg("access failed for file \"%s\": %m", srcsegpath)));
		return false;
	}
	sprintf(dstsegpath, "%s.%u", dstpath, segno);
	copy_file(srcsegpath, dstsegpath, dst, segno, use_wal);


	return true;
}

