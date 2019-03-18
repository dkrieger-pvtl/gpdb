#!/usr/bin/env python

import unittest
import tempfile
import os
from os import path
import filecmp

def setUpModule():
    global rootResultDir
    rootResultDir = tempfile.mkdtemp(dir='test/results')
    print(rootResultDir + "type: " + str(type(rootResultDir)))

def tearDownModule():
    print("NOTE: result files are in the directory: " + rootResultDir)
    #TODO: if successful test, delete tmpdir...

class AbstractTestCase(unittest.TestCase):
    def setUp(self):
        print("\nsetup...." + unittest.TestCase.id(self) + '\n')

    def tearDown(self):
        print("\nteardown...\n")

class TestBasicGraph(AbstractTestCase):

    def test_basic_deps(self):
        testFile = 'deps.txt'
        expectedFile = path.join('test/expected', testFile + ".gv")
        outFile = path.join(rootResultDir, testFile + ".gv")
        cmd = "./gp_graph_deptable.py -o " + path.join('test/input',testFile) + " -d " + rootResultDir
        print("running: " + cmd)
        os.system(cmd)
        self.assertTrue(filecmp.cmp(expectedFile, outFile), "comparing: %s with %s" % (expectedFile, outFile))

class TestBasicGraphCompare(AbstractTestCase):

    def test_basic_deps_compare(self):
        testFile1 = 'deps.txt'
        testFile2 = 'deps_add.txt'
        expectedFile12 = testFile1 + '_diff_' + testFile2 + ".gv"
        expectedFileName1 = path.join('test/expected', testFile1 + ".gv")
        expectedFileName2 = path.join('test/expected', testFile2 + ".gv")
        expectedFileName12 = path.join('test/expected', expectedFile12)
        resultFileName1 = path.join(rootResultDir, testFile1 + ".gv")
        resultFileName2 = path.join(rootResultDir, testFile2 + ".gv")
        resultFileName12 = path.join(rootResultDir, expectedFile12)

        cmd = "./gp_graph_deptable.py -o " + path.join('test/input',testFile1) + " -n " + \
              path.join('test/input', testFile2) + " -d " + rootResultDir
        print("running: " + cmd)
        os.system(cmd)
        self.assertTrue(filecmp.cmp(expectedFileName1, resultFileName1), "comparing: %s with %s" % (expectedFileName1, resultFileName1))
        self.assertTrue(filecmp.cmp(expectedFileName2, resultFileName2), "comparing: %s with %s" % (expectedFileName2, resultFileName2))
        # TODO: smart compare tool...
        self.assertTrue(filecmp.cmp(expectedFileName12, resultFileName12), "comparing: %s with %s" % (expectedFileName12, resultFileName12))

if __name__ == '__main__':
    unittest.main()