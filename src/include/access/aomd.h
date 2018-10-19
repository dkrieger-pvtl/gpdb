/*-------------------------------------------------------------------------
 *
 * aomd.h
 *	  Declarations and functions for supporting aomd.c
 *
 * Portions Copyright (c) 2008, Greenplum Inc.
 * Portions Copyright (c) 2012-Present Pivotal Software, Inc.
 *
 *
 * IDENTIFICATION
 *	    src/include/access/aomd.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef AOMD_H
#define AOMD_H

#include "htup_details.h"
#include "storage/fd.h"
#include "utils/rel.h"

extern int AOSegmentFilePathNameLen(Relation rel);

extern void FormatAOSegmentFileName(
						char *basepath,
						int segno,
						int col,
						int32 *fileSegNo,
						char *filepathname);

extern void MakeAOSegmentFileName(
					  Relation rel,
					  int segno,
					  int col,
					  int32 *fileSegNo,
					  char *filepathname);

extern File OpenAOSegmentFile(Relation rel,
				  char *filepathname,
				  int32 segmentFileNum,
				  int64	logicalEof);

extern void CloseAOSegmentFile(File fd);

extern void
TruncateAOSegmentFile(File fd,
					  Relation rel,
					  int32 segmentFileNum,
					  int64 offset);

extern void
mdunlink_ao(const char *path);
extern void
copy_append_only_data(RelFileNode src, RelFileNode dst, BackendId backendid, char relpersistence);

/* ADD COMMENTS */
typedef enum
{
	PG_UPGRADE = 1,
	MD_UNLINK  = 2,
	COPY_FILES = 3
} aoRelfileOperation_t;

typedef struct aoRelFileOperationData {
	aoRelfileOperation_t operation;
	union {
		struct {
			void *pageConverter;
			void *map;
		} pg_upgrade;
		struct {
			char *segpath;
			char *segpath_suffix_position;
		} md_unlink;
		struct {
			char *srcpath;
			char *dstpath;
            RelFileNode dst;
			bool useWal;
		} copy_files;
	} data;
} aoRelFileOperationData_t;


typedef bool (*aoRelFileFunction_t)(const int segno, const aoRelfileOperation_t operation,
									const aoRelFileOperationData_t *user_data);

extern void
aoRelfileOperationExecute(aoRelFileFunction_t relfileOperation,
                          const aoRelfileOperation_t operation,
                          const aoRelFileOperationData_t *user_data);

#endif							/* AOMD_H */
