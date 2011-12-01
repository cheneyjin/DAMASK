#!/usr/bin/python

import os,re,sys,math,string,numpy,DAMASK
from optparse import OptionParser, Option

# -----------------------------
class extendableOption(Option):
# -----------------------------
# used for definition of new option parser action 'extend', which enables to take multiple option arguments
# taken from online tutorial http://docs.python.org/library/optparse.html
  
  ACTIONS = Option.ACTIONS + ("extend",)
  STORE_ACTIONS = Option.STORE_ACTIONS + ("extend",)
  TYPED_ACTIONS = Option.TYPED_ACTIONS + ("extend",)
  ALWAYS_TYPED_ACTIONS = Option.ALWAYS_TYPED_ACTIONS + ("extend",)

  def take_action(self, action, dest, opt, value, values, parser):
    if action == "extend":
      lvalue = value.split(",")
      values.ensure_value(dest, []).extend(lvalue)
    else:
      Option.take_action(self, action, dest, opt, value, values, parser)

def location(idx,res):

  return ( idx  % res[0], \
          (idx // res[0]) % res[1], \
          (idx // res[0] // res[1]) % res[2] )

def index(location,res):

  return ( location[0] % res[0]                    + \
          (location[1] % res[1]) * res[0]          + \
          (location[2] % res[2]) * res[0] * res[1]   )        
# --------------------------------------------------------------------
#                                MAIN
# --------------------------------------------------------------------

parser = OptionParser(option_class=extendableOption, usage='%prog options file[s]', description = """
Add column containing debug information
Operates on periodic ordered three-dimensional data sets.

""" + string.replace('$Id$','\n','\\n')
)


parser.add_option('--no-shape','-s',    dest='shape', action='store_false', \
                                        help='do not calcuate shape mismatch [%default]')
parser.add_option('--no-volume','-v',   dest='volume', action='store_false', \
                                        help='do not calculate volume mismatch [%default]')
parser.add_option('-d','--dimension',   dest='dim', type='float', nargs=3, \
                                        help='physical dimension of data set in x (fast) y z (slow) [%default]')
parser.add_option('-r','--resolution',  dest='res', type='int', nargs=3, \
                                        help='resolution of data set in x (fast) y z (slow)')
parser.add_option('-f','--deformation', dest='defgrad', action='extend', type='string', \
                                        help='heading(s) of columns containing deformation tensor values %default')

parser.set_defaults(volume = True)
parser.set_defaults(shape = True)
parser.set_defaults(defgrad     = ['f'])

(options,filenames) = parser.parse_args()

if not options.res or len(options.res) < 3:
  parser.error('improper resolution specification...')
if not options.dim or len(options.dim) < 3:
  parser.error('improper dimension specification...')

defgrad        = {}
defgrad_av     = {}
centroids      = {}
nodes          = {}
shape_mismatch = {}
volume_mismatch= {}

datainfo = {                                                               # list of requested labels per datatype
             'defgrad':     {'len':9,
                             'label':[]},
           }

if options.defgrad != None:   datainfo['defgrad']['label'] += options.defgrad

# ------------------------------------------ setup file handles ---------------------------------------  

files = []
if filenames == []:
  parser.error('no data file specified')
else:
  for name in filenames:
    if os.path.exists(name):
      files.append({'name':name, 'input':open(name), 'output':open(name+'_tmp','w')})

# ------------------------------------------ loop over input files ---------------------------------------  

for file in files:
  print file['name']

  #  get labels by either read the first row, or - if keyword header is present - the last line of the header

  firstline = file['input'].readline()
  m = re.search('(\d+)\s*head', firstline.lower())
  if m:
    headerlines = int(m.group(1))
    passOn  = [file['input'].readline() for i in range(1,headerlines)]
    headers = file['input'].readline().split()
  else:
    headerlines = 1
    passOn  = []
    headers = firstline.split()

  data = file['input'].readlines()

  for i,l in enumerate(headers):
    if l.startswith('1_'):
      if re.match('\d+_',l[2:]) or i == len(headers)-1 or not headers[i+1].endswith(l[2:]):
        headers[i] = l[2:]

  active = {}
  column = {}
  head = []

  for datatype,info in datainfo.items():
    for label in info['label']:
      key = {True :'1_%s',
             False:'%s'   }[info['len']>1]%label
      if key not in headers:
        sys.stderr.write('column %s not found...\n'%key)
      else:
        if datatype not in active: active[datatype] = []
        if datatype not in column: column[datatype] = {}
        active[datatype].append(label)
        column[datatype][label] = headers.index(key)
        if options.shape:  head += ['mismatch_shape(%s)'%label]
        if options.volume: head += ['mismatch_volume(%s)'%label]

# ------------------------------------------ assemble header ---------------------------------------  

  output = '%i\theader'%(headerlines+1) + '\n' + \
           ''.join(passOn) + \
           string.replace('$Id$','\n','\\n')+ '\t' + \
           ' '.join(sys.argv[1:]) + '\n' + \
           '\t'.join(headers + head) + '\n'                              # build extended header


# ------------------------------------------ read deformation tensors ---------------------------------------  

  for datatype,labels in active.items():
    for label in labels:
      defgrad[label] = numpy.array([0.0 for i in xrange(9*options.res[0]*options.res[1]*options.res[2])],'d').\
                                                 reshape((options.res[0],options.res[1],options.res[2],3,3))
  
      idx = 0
      for line in data:
        items = line.split()[:len(headers)]                    # take only valid first items
        if len(items) < len(headers):                          # too short lines get dropped
          continue

        defgrad[label][location(idx,options.res)[0]]\
                      [location(idx,options.res)[1]]\
                      [location(idx,options.res)[2]]\
                = numpy.array(map(float,items[column[datatype][label]:
                                              column[datatype][label]+datainfo[datatype]['len']]),'d').reshape(3,3)
        idx += 1                                                   
      print options.res
      defgrad_av[label] = DAMASK.math.tensor_avg(options.res,defgrad[label])
      centroids[label] = DAMASK.math.deformed_fft(options.res,options.dim,defgrad_av[label],1.0,defgrad[label])
      nodes[label] = DAMASK.math.mesh_regular_grid(options.res,options.dim,defgrad_av[label],centroids[label])
      if options.shape:   shape_mismatch[label] = DAMASK.math.shape_compare( options.res,options.dim,defgrad[label],nodes[label],centroids[label])
      if options.volume: volume_mismatch[label] = DAMASK.math.volume_compare(options.res,options.dim,defgrad[label],nodes[label])

# ------------------------------------------ read file ---------------------------------------  

  idx = 0
  for line in data:
    items = line.split()[:len(headers)]
    if len(items) < len(headers):
      continue
  
    output += '\t'.join(items)

    for datatype,labels in active.items():
      for label in labels:

        if options.shape:  output += '\t%f'%shape_mismatch[label][location(idx,options.res)[0]][location(idx,options.res)[1]][location(idx,options.res)[2]]
        if options.volume: output += '\t%f'%volume_mismatch[label][location(idx,options.res)[0]][location(idx,options.res)[1]][location(idx,options.res)[2]]
          
    output += '\n'
    idx += 1  

  file['input'].close()

# ------------------------------------------ output result ---------------------------------------  

  file['output'].write(output)
  file['output'].close
  os.rename(file['name']+'_tmp',file['name'])
