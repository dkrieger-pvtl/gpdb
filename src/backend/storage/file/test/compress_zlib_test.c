#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include <zconf.h>
#include "cmockery.h"

#include "c.h"

/* Ignore ereport */
#include "utils/elog.h"
#include "fstream/gfile.h"


#undef ereport
#undef errcode
#undef errmsg
#define ereport
#define errcode
#define errmsg

#include "utils/palloc.h"
#include "utils/memutils.h"

#include "../compress_zlib.c"

static MemoryContext *compress_zlib_context;

/* ==================== bfz_zlib_init =================== */
/*
 * Tests that bfz_zlib_init uses palloc() to allocate memory
 * for zlib internal buffers.
 */

/*
 * Returns the amount of memory needed for zlib internal allocations
 *
 *   isWrite: Set to true if opening a file for writing
 */
int
zlib_memory_needed(bool isWrite) {

	/*
	 * This values are set in zconf.h, based on local configuration
	 */
	int def_mem_level = MAX_MEM_LEVEL;
	if (MAX_MEM_LEVEL >= 8) {
		def_mem_level = 8;
	}
	int def_wbits = MAX_WBITS;
	int memZlib = -1;

	/*
	 * The formula for computing the memory needed is described in
	 * zconf.h. For zlib 1.2.3, it is as follows:
	 *
	 * The memory requirements for deflate are (in bytes):
	 *      (1 << (windowBits+2)) +  (1 << (memLevel+9))
	 * that is: 128K for windowBits=15  +  128K for memLevel = 8
	 * (default values) plus a few kilobytes for small objects.
	 *
	 * The memory requirements for inflate are (in bytes)
	 *      1 << windowBits
	 * that is, 32K for windowBits=15 (default value) plus a few
	 * kilobytes for small objects.
	 */
	if (isWrite) {
		memZlib =  (1 << (def_wbits+2)) +  (1 << (def_mem_level+9));
	}
	else {
		memZlib = (1 << def_wbits);
	}

	return memZlib;
}

void
test__bfz_zlib_init__palloc_write(void **state)
{

	bfz_t bfz;

	bfz.mode = BFZ_MODE_APPEND;
	bfz.fd = -1;

	Size beforeAlloc = MemoryContextGetPeakSpace(compress_zlib_context);
	assert_true(compress_zlib_context == CurrentMemoryContext);

	bfz_zlib_init(&bfz);

	Size afterAlloc = MemoryContextGetPeakSpace(compress_zlib_context);
	assert_true(compress_zlib_context == CurrentMemoryContext);

	int memZlib = zlib_memory_needed(true /* isWrite */);

	assert_true(afterAlloc - beforeAlloc > memZlib);
}

void
test__bfz_zlib_init__palloc_read(void **state)
{

	bfz_t bfz;

	bfz.mode = BFZ_MODE_SCAN;
	bfz.fd = -1;

	Size beforeAlloc = MemoryContextGetPeakSpace(compress_zlib_context);
	assert_true(compress_zlib_context == CurrentMemoryContext);

	bfz_zlib_init(&bfz);

	Size afterAlloc = MemoryContextGetPeakSpace(compress_zlib_context);
	assert_true(compress_zlib_context == CurrentMemoryContext);

	int memZlib = zlib_memory_needed(false /* isWrite */);

	assert_true(afterAlloc - beforeAlloc > memZlib);
}

int
main(int argc, char* argv[])
{
	cmockery_parse_arguments(argc, argv);

	const UnitTest tests[] = {
		unit_test(test__bfz_zlib_init__palloc_write),
		unit_test(test__bfz_zlib_init__palloc_read)
	};


	MemoryContextInit();

	compress_zlib_context =
		AllocSetContextCreate(TopMemoryContext,
							  "compress_zlib_context",
							  ALLOCSET_DEFAULT_MINSIZE,
							  ALLOCSET_DEFAULT_INITSIZE,
							  ALLOCSET_DEFAULT_MAXSIZE);

	MemoryContextSwitchTo(compress_zlib_context);

	return run_tests(tests);
}
