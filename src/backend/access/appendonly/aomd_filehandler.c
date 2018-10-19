/*-------------------------------------------------------------------------
 *
 * aomd_filehandler.c
 *	  Code in this file would have been in aomd.c but is needed in contrib,
 * so we separate it out here.
 *
 * Portions Copyright (c) 2008, Greenplum Inc.
 * Portions Copyright (c) 2012-Present Pivotal Software, Inc.
 * Portions Copyright (c) 1996-2008, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	    src/backend/access/appendonly/aomd_filehandler.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "access/aomd.h"
#include "access/appendonlytid.h"
#include "access/appendonlywriter.h"

void
aoRelfileOperationExecute(aoRelFileFunction_t relfileOperation,
                          const aoRelfileOperation_t operation,
                          const aoRelFileOperationData_t *user_data) {

    int segno;
    int colnum;
    int segNumberArray[AOTupleId_MaxSegmentFileNum];
    int segNumberArraySize;

    /*
     * The 0 based extensions such as .128, .256, ... for CO tables are
     * created by ALTER table or utility mode insert. These also need to be
     * copied; however, they may not exist hence are treated separately
     * here. Column 0 concurrency level 0 file is always present.
     */
    for (colnum = 1; colnum <= MaxHeapAttributeNumber; colnum++) {
        segno = colnum * AOTupleId_MultiplierSegmentFileNum;
        if (!relfileOperation(segno, operation, user_data))
            break;
    }

    segNumberArraySize = 0;
    for (segno = 1; segno < MAX_AOREL_CONCURRENCY; segno++) {
        if (!relfileOperation(segno, operation, user_data))
            continue;
        segNumberArray[segNumberArraySize] = segno;
        segNumberArraySize++;
    }

    for (int i = 0; i < segNumberArraySize; i++) {
        for (colnum = 1; colnum <= MaxHeapAttributeNumber; colnum++) {
            segno = colnum * AOTupleId_MultiplierSegmentFileNum + segNumberArray[i];
            if (!relfileOperation(segno, operation, user_data))
                break;
        }
    }

    return;
}