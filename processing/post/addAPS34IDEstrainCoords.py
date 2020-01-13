#!/usr/bin/env python3

import os
import sys
from io import StringIO
from optparse import OptionParser

import numpy as np

import damask


scriptName = os.path.splitext(os.path.basename(__file__))[0]
scriptID   = ' '.join([scriptName,damask.version])


# --------------------------------------------------------------------
#                                MAIN
# --------------------------------------------------------------------

parser = OptionParser(option_class=damask.extendableOption, usage='%prog options [ASCIItable(s)]', description = """
Transform X,Y,Z,F APS BeamLine 34 coordinates to x,y,z APS strain coordinates.

""", version = scriptID)

parser.add_option('-f','--frame',dest='frame', metavar='string',
                                 help='label of APS X,Y,Z coords')
parser.add_option('--depth',     dest='depth', metavar='string',
                                 help='depth')

(options,filenames) = parser.parse_args()
if filenames == []: filenames = [None]

if options.frame is None:
  parser.error('frame not specified')
if options.depth is None:
  parser.error('depth not specified')


theta=-0.75*np.pi
RotMat2TSL=np.array([[1.,  0.,            0.],
                     [0.,  np.cos(theta), np.sin(theta)],                                           # Orientation to account for -135 deg
                     [0., -np.sin(theta), np.cos(theta)]])                                          # rotation for TSL convention

for name in filenames:
    damask.util.report(scriptName,name)

    table = damask.Table.from_ASCII(StringIO(''.join(sys.stdin.read())) if name is None else name)
    
    coord      = - table.get(options.frame)
    coord[:,2] += table.get(options.depth)[:,0]

    table.add('coord',
              np.einsum('ijk,ik->ij',np.broadcast_to(RotMat2TSL,(coord.shape[0],3,3)),coord),
              scriptID+' '+' '.join(sys.argv[1:]))

    table.to_ASCII(sys.stdout if name is None else name)
