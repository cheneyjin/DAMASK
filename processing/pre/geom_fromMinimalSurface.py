#!/usr/bin/env python
# -*- coding: UTF-8 no BOM -*-

import os,sys,string,math
import numpy as np
from optparse import OptionParser
import damask

scriptID   = string.replace('$Id$','\n','\\n')
scriptName = os.path.splitext(scriptID.split()[1])[0]

# --------------------------------------------------------------------
#                                MAIN
# --------------------------------------------------------------------

minimal_surfaces = ['primitive','gyroid','diamond',]

surface = {
            'primitive': lambda x,y,z: math.cos(x)+math.cos(y)+math.cos(z),
            'gyroid':    lambda x,y,z: math.sin(x)*math.cos(y)+math.sin(y)*math.cos(z)+math.cos(x)*math.sin(z),
            'diamond':   lambda x,y,z: math.cos(x-y)*math.cos(z)+math.sin(x+y)*math.sin(z),
          }

parser = OptionParser(option_class=damask.extendableOption, usage='%prog', description = """
Generate a geometry file of a bicontinuous structure of given type.

""", version = scriptID)


parser.add_option('-t','--type', dest='type', choices=minimal_surfaces, metavar='string', \
                  help='type of minimal surface [primitive] {%s}' %(','.join(minimal_surfaces)))
parser.add_option('-f','--threshold', dest='threshold', type='float', metavar='float', \
                  help='threshold value defining minimal surface [%default]')
parser.add_option('-g', '--grid', dest='grid', type='int', nargs=3, metavar='int int int', \
                  help='a,b,c grid of hexahedral box [%default]')
parser.add_option('-s', '--size', dest='size', type='float', nargs=3, metavar='float float float', \
                  help='x,y,z size of hexahedral box [%default]')
parser.add_option('-p', '--periods', dest='periods', type='int', metavar= 'int', \
                  help='number of repetitions of unit cell [%default]')
parser.add_option('--homogenization', dest='homogenization', type='int', metavar= 'int', \
                  help='homogenization index to be used [%default]')
parser.add_option('--m', dest='microstructure', type='int', nargs = 2, metavar= 'int int', \
                  help='two microstructure indices to be used [%default]')
parser.add_option('-2', '--twodimensional', dest='twoD', action='store_true', \
                  help='output geom file with two-dimensional data arrangement [%default]')
parser.set_defaults(type = minimal_surfaces[0])
parser.set_defaults(threshold = 0.0)
parser.set_defaults(periods = 1)
parser.set_defaults(grid = (16,16,16))
parser.set_defaults(size = (1.0,1.0,1.0))
parser.set_defaults(homogenization = 1)
parser.set_defaults(microstructure = (1,2))
parser.set_defaults(twoD  = False)

(options,filename) = parser.parse_args()

# ------------------------------------------ setup file handle -------------------------------------
if filename == []:
  file = {'output':sys.stdout, 'croak':sys.stderr}
else:
  file = {'output':open(filename[0],'w'), 'croak':sys.stderr}

info = {
        'grid':   np.array(options.grid),
        'size':   np.array(options.size),
        'origin': np.zeros(3,'d'),
        'microstructures': max(options.microstructure),
        'homogenization':  options.homogenization
       }

#--- report ---------------------------------------------------------------------------------------
file['croak'].write('\033[1m'+scriptName+'\033[0m\n')
file['croak'].write('grid     a b c:  %s\n'%(' x '.join(map(str,info['grid']))) + \
                    'size     x y z:  %s\n'%(' x '.join(map(str,info['size']))) + \
                    'origin   x y z:  %s\n'%(' : '.join(map(str,info['origin']))) + \
                    'homogenization:  %i\n'%info['homogenization'] + \
                    'microstructures: %i\n\n'%info['microstructures'])

if np.any(info['grid'] < 1):
  file['croak'].write('invalid grid a b c.\n')
  sys.exit()
if np.any(info['size'] <= 0.0):
  file['croak'].write('invalid size x y z.\n')
  sys.exit()

#--- write header ---------------------------------------------------------------------------------
header = [scriptID + ' ' + ' '.join(sys.argv[1:])+'\n']
header.append("grid\ta %i\tb %i\tc %i\n"%(info['grid'][0],info['grid'][1],info['grid'][2],))
header.append("size\tx %f\ty %f\tz %f\n"%(info['size'][0],info['size'][1],info['size'][2],))
header.append("origin\tx %f\ty %f\tz %f\n"%(info['origin'][0],info['origin'][1],info['origin'][2],))
header.append("microstructures\t%i\n"%info['microstructures'])
header.append("homogenization\t%i\n"%info['homogenization'])
file['output'].write('%i\theader\n'%(len(header))+''.join(header))

#--- write data -----------------------------------------------------------------------------------
for z in xrange(options.grid[2]):
  Z = options.periods*2.0*math.pi*(z+0.5)/options.grid[2]
  for y in xrange(options.grid[1]):
    Y = options.periods*2.0*math.pi*(y+0.5)/options.grid[1]
    for x in xrange(options.grid[0]):
      X = options.periods*2.0*math.pi*(x+0.5)/options.grid[0]
      file['output'].write(str(options.microstructure[0]) if options.threshold > surface[options.type](X,Y,Z)
                      else str(options.microstructure[1]))
      file['output'].write(' ' if options.twoD else '\n')
    file['output'].write('\n' if options.twoD else '')
