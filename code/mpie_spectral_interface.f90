!* $Id: mpie_spectral_interface.f90 605 2010-07-07 09:10:54Z MPIE\m.diehl $
!********************************************************************

MODULE mpie_interface
 use prec, only: pInt, pReal
 character(len=64), parameter :: FEsolver = 'Spectral'
 character(len=5),  parameter :: InputFileExtension = '.mesh'

CONTAINS

!********************************************************************
! initialize interface module
!
!********************************************************************
subroutine mpie_interface_init()

 write(6,*)
 write(6,*) '<<<+-  mpie_spectral init  -+>>>'
 write(6,*) '$Id: mpie_spectral_interface.f90 605 2010-07-07 09:10:54Z MPIE\m.diehl $'
 write(6,*)

 return
endsubroutine

!********************************************************************
! extract working directory from loadcase file
! possibly based on current working dir
!********************************************************************
function getSolverWorkingDirectoryName()

 implicit none

 character(len=1024) cwd,outname,getSolverWorkingDirectoryName
 character(len=*), parameter :: pathSep = achar(47)//achar(92) ! forwardslash, backwardslash

 call getarg(2,outname)                                ! path to loadFile

 if (scan(outname,pathSep) == 1) then                  ! absolute path given as command line argument
   getSolverWorkingDirectoryName = outname(1:scan(outname,pathSep,back=.true.))
 else
   call getcwd(cwd)
   getSolverWorkingDirectoryName = trim(cwd)//'/'//outname(1:scan(outname,pathSep,back=.true.))
 endif

 getSolverWorkingDirectoryName = rectifyPath(getSolverWorkingDirectoryName)

 return

endfunction

!********************************************************************
! basename of meshfile from command line arguments
!
!********************************************************************
function getSolverJobName()

 use prec, only: pInt

 implicit none

 character(1024) getSolverJobName, outName, cwd
 character(len=*), parameter :: pathSep = achar(47)//achar(92) ! /, \
 integer(pInt) posExt,posSep

 getSolverJobName = ''

 call getarg(1,outName)
 posExt = scan(outName,'.',back=.true.)
 posSep = scan(outName,pathSep,back=.true.)

 if (posExt <= posSep) posExt = len_trim(outName)+1       ! no extension present
 getSolverJobName = outName(1:posExt-1)                   ! path to mesh file (excl. extension)

 if (scan(getSolverJobName,pathSep) /= 1) then            ! relative path given as command line argument
   call getcwd(cwd)
   getSolverJobName = rectifyPath(trim(cwd)//'/'//getSolverJobName)
 else
   getSolverJobName = rectifyPath(getSolverJobName)
 endif

 getSolverJobName = makeRelativePath(getSolverWorkingDirectoryName(),&
                                    getSolverJobName)
 return
endfunction


!********************************************************************
! relative path of loadcase from command line arguments
!
!********************************************************************
function getLoadcaseName()

 use prec, only: pInt

 implicit none

 character(len=1024) getLoadcaseName, outName, cwd
 character(len=*), parameter :: pathSep = achar(47)//achar(92) ! /, \
 integer(pInt) posExt,posSep
 posExt = 0

 call getarg(2,getLoadcaseName)
 posExt = scan(getLoadcaseName,'.',back=.true.)
 posSep = scan(getLoadcaseName,pathSep,back=.true.)

 if (posExt <= posSep) getLoadcaseName = trim(getLoadcaseName)//('.load')   ! no extension present
 if (scan(getLoadcaseName,pathSep) /= 1) then          ! relative path given as command line argument
   call getcwd(cwd)
   getLoadcaseName = rectifyPath(trim(cwd)//'/'//getLoadcaseName)
 else
   getLoadcaseName = rectifyPath(getLoadcaseName)
 endif

 getLoadcaseName = makeRelativePath(getSolverWorkingDirectoryName(),&
                                    getLoadcaseName)
 return
endfunction


!********************************************************************
! remove ../ and ./ from path
!
!********************************************************************
function rectifyPath(path)

 use prec, only: pInt

 implicit none

 character(len=*) path
 character(len=len_trim(path)) rectifyPath
 integer(pInt) i,j,k,l

 !remove ./ from path
 l = len_trim(path)
 rectifyPath = path
 do i = l,2,-1
    if ( rectifyPath(i-1:i) == './' .and. rectifyPath(i-2:i-2) /= '.' ) &
      rectifyPath(i-1:l) = rectifyPath(i+1:l)//'  '
 enddo

 !remove ../ and corresponding directory from rectifyPath
 l = len_trim(rectifyPath)
 i = index(rectifyPath(i:l),'../')
 j = 0_pInt
 do while (i > j)
    j = scan(rectifyPath(:i-2),'/',back=.true.)
    rectifyPath(j+1:l) = rectifyPath(i+3:l)//repeat(' ',2+i-j)
    i = j+index(rectifyPath(j+1:l),'../')
 enddo
 if(len_trim(rectifyPath) == 0) rectifyPath = '/'
 return
 endfunction rectifyPath


!********************************************************************
! relative path from absolute a to absolute b
!
!********************************************************************
function makeRelativePath(a,b)

 use prec, only: pInt

 implicit none

 character (len=*) :: a,b
 character (len=1024) :: makeRelativePath
 integer(pInt) i,posLastCommonSlash,remainingSlashes

 posLastCommonSlash = 0
 remainingSlashes = 0
 do i = 1,min(1024,len_trim(a),len_trim(b))
   if (a(i:i) /= b(i:i)) exit
   if (a(i:i) == '/') posLastCommonSlash = i
 enddo
 do i = posLastCommonSlash+1,len_trim(a)
   if (a(i:i) == '/') remainingSlashes = remainingSlashes + 1
 enddo
 makeRelativePath = repeat('../',remainingSlashes)//b(posLastCommonSlash+1:len_trim(b))
 return
endfunction makeRelativePath

END MODULE