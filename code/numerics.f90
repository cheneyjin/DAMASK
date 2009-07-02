!##############################################################
MODULE numerics
!##############################################################

use prec, only: pInt, pReal
implicit none

character(len=64), parameter :: numerics_configFile = 'numerics.config' ! name of configuration file
integer(pInt)                   iJacoStiffness, &                       ! frequency of stiffness update
                                iJacoLpresiduum, &                      ! frequency of Jacobian update of residuum in Lp
                                nHomog, &                               ! homogenization loop limit
                                nCryst, &                               ! crystallite loop limit (only for debugging info, real loop limit is "subStepMin")
                                nState, &                               ! state loop limit
                                nStress, &                              ! stress loop limit
                                NRiterMax                               ! maximum number of GIA iteration
real(pReal)                     relevantStrain, &                       ! strain increment considered significant
                                pert_Fg, &                              ! strain perturbation for FEM Jacobi
                                subStepMin, &                           ! minimum (relative) size of sub-step allowed during cutback in crystallite
                                rTol_crystalliteState, &                ! relative tolerance in crystallite state loop 
                                rTol_crystalliteTemperature, &          ! relative tolerance in crystallite temperature loop 
                                rTol_crystalliteStress, &               ! relative tolerance in crystallite stress loop
                                aTol_crystalliteStress, &               ! absolute tolerance in crystallite stress loop
                                resToler, &                             ! relative tolerance of residual in GIA iteration
                                resAbsol, &                             ! absolute tolerance of residual in GIA iteration (corresponds to ~1 Pa)
                                resBound                                ! relative maximum value (upper bound) for GIA residual
                                

CONTAINS
 
!*******************************************
!    initialization subroutine
!*******************************************
subroutine numerics_init()
  
  !*** variables and functions from other modules ***!
  use prec, only:                             pInt, & 
                                              pReal  
  use IO, only:                               IO_error, &
                                              IO_open_file, &
                                              IO_isBlank, &
                                              IO_stringPos, &
                                              IO_stringValue, &
                                              IO_lc, &
                                              IO_floatValue, &
                                              IO_intValue
  
  implicit none

  !*** input variables ***!
  
  !*** output variables ***!
  
  !*** local variables ***!
  integer(pInt), parameter ::                 fileunit = 300  
  integer(pInt), parameter ::                 maxNchunks = 2
  integer(pInt), dimension(1+2*maxNchunks) :: positions
  character(len=64)                           tag
  character(len=1024)                         line
  
  !*** global variables ***!
  ! relevantStrain
  ! iJacoStiffness
  ! iJacoLpresiduum
  ! pert_Fg
  ! nHomog
  ! nCryst
  ! nState
  ! nStress
  ! subStepMin
  ! rTol_crystalliteState
  ! rTol_crystalliteTemperature
  ! rTol_crystalliteStress
  ! aTol_crystalliteStress
  ! resToler
  ! resAbsol
  ! resBound
  ! NRiterMax
  
  write(6,*)
  write(6,*) '<<<+-  numerics init  -+>>>'
  write(6,*)
  
  ! initialize all parameters with standard values
  relevantStrain              = 1.0e-7_pReal
  iJacoStiffness              = 1_pInt
  iJacoLpresiduum             = 1_pInt
  pert_Fg                     = 1.0e-6_pReal
  nHomog                      = 10_pInt
  nCryst                      = 20_pInt
  nState                      = 10_pInt
  nStress                     = 40_pInt
  subStepMin                  = 1.0e-3_pReal
  rTol_crystalliteState       = 1.0e-6_pReal
  rTol_crystalliteTemperature = 1.0e-6_pReal
  rTol_crystalliteStress      = 1.0e-6_pReal
  aTol_crystalliteStress      = 1.0e-8_pReal
  resToler                    = 1.0e-4_pReal
  resAbsol                    = 1.0e+2_pReal
  resBound                    = 1.0e+1_pReal
  NRiterMax                   = 24_pInt

  ! try to open the config file
  if(IO_open_file(fileunit,numerics_configFile)) then 
  
    write(6,*) '   ... using values from config file'
    write(6,*)
    
    line = ''
    ! read variables from config file and overwrite parameters
    do
      read(fileunit,'(a1024)',END=100) line
      if (IO_isBlank(line)) cycle                           ! skip empty lines
      positions = IO_stringPos(line,maxNchunks)
      tag = IO_lc(IO_stringValue(line,positions,1))         ! extract key
      select case(tag)
        case ('relevantstrain')
              relevantStrain = IO_floatValue(line,positions,2)
        case ('ijacostiffness')
              iJacoStiffness = IO_intValue(line,positions,2)
        case ('ijacolpresiduum')
              iJacoLpresiduum = IO_intValue(line,positions,2)
        case ('pert_fg')
              pert_Fg = IO_floatValue(line,positions,2)
        case ('nhomog')
              nHomog = IO_intValue(line,positions,2)
        case ('ncryst')
              nCryst = IO_intValue(line,positions,2)
        case ('nstate')
              nState = IO_intValue(line,positions,2)
        case ('nstress')
              nStress = IO_intValue(line,positions,2)
        case ('substepmin')
              subStepMin = IO_floatValue(line,positions,2)
        case ('rtol_crystallitestate')
              rTol_crystalliteState = IO_floatValue(line,positions,2)
        case ('rtol_crystallitetemperature')
              rTol_crystalliteTemperature = IO_floatValue(line,positions,2)
        case ('rtol_crystallitestress')
              rTol_crystalliteStress = IO_floatValue(line,positions,2)
        case ('atol_crystallitestress')
              aTol_crystalliteStress = IO_floatValue(line,positions,2)
        case ('restoler')
              resToler = IO_floatValue(line,positions,2)
        case ('resabsol')
              resAbsol = IO_floatValue(line,positions,2)
        case ('resbound')
              resBound = IO_floatValue(line,positions,2)
        case ('nritermax')
              NRiterMax = IO_intValue(line,positions,2)
      endselect
    enddo
    100 close(fileunit)
  
  ! no config file, so we use standard values
  else 
  
    write(6,*) '   ... using standard values'
    write(6,*)
    
  endif

  ! writing parameters to output file
  write(6,'(a24,x,e8.1)') 'relevantStrain:         ',relevantStrain
  write(6,'(a24,x,i8)')   'iJacoStiffness:         ',iJacoStiffness
  write(6,'(a24,x,i8)')   'iJacoLpresiduum:        ',iJacoLpresiduum
  write(6,'(a24,x,e8.1)') 'pert_Fg:                ',pert_Fg
  write(6,'(a24,x,i8)')   'nHomog:                 ',nHomog
  write(6,'(a24,x,i8)')   'nCryst:                 ',nCryst
  write(6,'(a24,x,i8)')   'nState:                 ',nState
  write(6,'(a24,x,i8)')   'nStress:                ',nStress
  write(6,'(a24,x,e8.1)') 'subStepMin:             ',subStepMin
  write(6,'(a24,x,e8.1)') 'rTol_crystalliteState:  ',rTol_crystalliteState
  write(6,'(a24,x,e8.1)') 'rTol_crystalliteTemp:   ',rTol_crystalliteTemperature
  write(6,'(a24,x,e8.1)') 'rTol_crystalliteStress: ',rTol_crystalliteStress
  write(6,'(a24,x,e8.1)') 'aTol_crystalliteStress: ',aTol_crystalliteStress
  write(6,'(a24,x,e8.1)') 'resToler:               ',resToler
  write(6,'(a24,x,e8.1)') 'resAbsol:               ',resAbsol
  write(6,'(a24,x,e8.1)') 'resBound:               ',resBound
  write(6,'(a24,x,i8)')   'NRiterMax:              ',NRiterMax
  write(6,*)
  
  ! sanity check
  if (relevantStrain <= 0.0_pReal)              call IO_error(260)
  if (iJacoStiffness < 1_pInt)                  call IO_error(261)
  if (iJacoLpresiduum < 1_pInt)                 call IO_error(262)
  if (pert_Fg <= 0.0_pReal)                     call IO_error(263)
  if (nHomog < 1_pInt)                          call IO_error(264)
  if (nCryst < 1_pInt)                          call IO_error(265)
  if (nState < 1_pInt)                          call IO_error(266)
  if (nStress < 1_pInt)                         call IO_error(267)
  if (subStepMin <= 0.0_pReal)                  call IO_error(268)
  if (rTol_crystalliteState <= 0.0_pReal)       call IO_error(269)
  if (rTol_crystalliteTemperature <= 0.0_pReal) call IO_error(276)
  if (rTol_crystalliteStress <= 0.0_pReal)      call IO_error(270)
  if (aTol_crystalliteStress <= 0.0_pReal)      call IO_error(271)
  if (resToler <= 0.0_pReal)                    call IO_error(272)
  if (resAbsol <= 0.0_pReal)                    call IO_error(273)
  if (resBound <= 0.0_pReal)                    call IO_error(274)
  if (NRiterMax < 1_pInt)                       call IO_error(275)
 
endsubroutine

END MODULE numerics