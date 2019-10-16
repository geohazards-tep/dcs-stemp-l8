#!/opt/anaconda/bin/python

import sys
import os
import unittest
import string
from StringIO import StringIO

class NodeATestCase(unittest.TestCase):

    def setUp(self):
        pass

    def test_log(self):
        self.assertEqual("1", "1")

if __name__ == '__main__':
    unittest.main()
