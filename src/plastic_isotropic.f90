!--------------------------------------------------------------------------------------------------
!> @author Franz Roters, Max-Planck-Institut für Eisenforschung GmbH
!> @author Philip Eisenlohr, Max-Planck-Institut für Eisenforschung GmbH
!> @brief material subroutine for isotropic (ISOTROPIC) plasticity
!> @details Isotropic (ISOTROPIC) Plasticity which resembles the phenopowerlaw plasticity without
!! resolving the stress on the slip systems. Will give the response of phenopowerlaw for an
!! untextured polycrystal
!--------------------------------------------------------------------------------------------------
module plastic_isotropic
 use prec, only: &
   pReal,&
   pInt
 
 implicit none
 private
 integer(pInt),                       dimension(:),     allocatable,         public, protected :: &
   plastic_isotropic_sizePostResults                                                                  !< cumulative size of post results
   
 integer(pInt),                       dimension(:,:),   allocatable, target, public :: &
   plastic_isotropic_sizePostResult                                                                   !< size of each post result output
   
 character(len=64),                   dimension(:,:),   allocatable, target, public :: &
   plastic_isotropic_output                                                                           !< name of each post result output
 
 integer(pInt),                       dimension(:),     allocatable, target, public :: &
   plastic_isotropic_Noutput                                                                          !< number of outputs per instance
 
 enum, bind(c) 
   enumerator :: undefined_ID, &
                 flowstress_ID, &
                 strainrate_ID
 end enum

 type, private :: tParameters                                                                         !< container type for internal constitutive parameters
   integer(kind(undefined_ID)), allocatable, dimension(:) :: & 
     outputID
  real(pReal) :: &
     fTaylor, &
     tau0, &
     gdot0, &
     n, &
     h0, &
     h0_slopeLnRate = 0.0_pReal, &
     tausat, &
     a, &
     aTolFlowstress = 1.0_pReal, &
     aTolShear      = 1.0e-6_pReal, &
     tausat_SinhFitA= 0.0_pReal, &
     tausat_SinhFitB= 0.0_pReal, &
     tausat_SinhFitC= 0.0_pReal, &
     tausat_SinhFitD= 0.0_pReal
  logical :: &
     dilatation = .false.
 end type

 type(tParameters), dimension(:), allocatable, target, private :: param                               !< containers of constitutive parameters (len Ninstance)
 
 type, private :: tIsotropicState                                                                     !< internal state aliases
   real(pReal), pointer,     dimension(:) :: &                                                        ! scalars along NipcMyInstance
     flowstress, &
     accumulatedShear
 end type

 type(tIsotropicState), allocatable, dimension(:), private :: &                                       !< state aliases per instance
   state, &
   dotState

 public  :: &
   plastic_isotropic_init, &
   plastic_isotropic_LpAndItsTangent, &
   plastic_isotropic_LiAndItsTangent, &
   plastic_isotropic_dotState, &
   plastic_isotropic_postResults

contains


!--------------------------------------------------------------------------------------------------
!> @brief module initialization
!> @details reads in material parameters, allocates arrays, and does sanity checks
!--------------------------------------------------------------------------------------------------
subroutine plastic_isotropic_init(fileUnit)
#if defined(__GFORTRAN__) || __INTEL_COMPILER >= 1800
 use, intrinsic :: iso_fortran_env, only: &
   compiler_version, &
   compiler_options
#endif
 use debug, only: &
   debug_level, &
   debug_constitutive, &
   debug_levelBasic
 use numerics, only: &
   numerics_integrator
 use math, only: &
   math_Mandel3333to66, &
   math_Voigt66to3333
 use IO, only: &
   IO_read, &
   IO_lc, &
   IO_getTag, &
   IO_isBlank, &
   IO_stringPos, &
   IO_stringValue, &
   IO_floatValue, &
   IO_error, &
   IO_timeStamp, &
   IO_EOF
 use material, only: &
   phase_plasticity, &
   phase_plasticityInstance, &
   phase_Noutput, &
   PLASTICITY_ISOTROPIC_label, &
   PLASTICITY_ISOTROPIC_ID, &
   material_phase, &
   plasticState, &
   MATERIAL_partPhase
   
 use lattice  

 implicit none
 integer(pInt), intent(in) :: fileUnit
 
 type(tParameters), pointer :: p
 
 integer(pInt), allocatable, dimension(:) :: chunkPos
 integer(pInt) :: &
   o, &
   phase, & 
   instance, &
   maxNinstance, &
   mySize, &
   sizeDotState, &
   sizeState, &
   sizeDeltaState
 character(len=65536) :: &
   tag       = '', &
   line      = '', &
   extmsg    = ''
 character(len=64) :: &
   outputtag = ''
 integer(pInt) :: NipcMyPhase

 write(6,'(/,a)')   ' <<<+-  constitutive_'//PLASTICITY_ISOTROPIC_label//' init  -+>>>'
 write(6,'(/,a)')   ' Ma et al., Computational Materials Science, 109:323–329, 2015'
 write(6,'(/,a)')   ' https://doi.org/10.1016/j.commatsci.2015.07.041'
 write(6,'(a15,a)') ' Current time: ',IO_timeStamp()
#include "compilation_info.f90"
 
 maxNinstance = int(count(phase_plasticity == PLASTICITY_ISOTROPIC_ID),pInt)
 if (maxNinstance == 0_pInt) return

 if (iand(debug_level(debug_constitutive),debug_levelBasic) /= 0_pInt) &
   write(6,'(a16,1x,i5,/)') '# instances:',maxNinstance

 allocate(plastic_isotropic_sizePostResults(maxNinstance),                      source=0_pInt)
 allocate(plastic_isotropic_sizePostResult(maxval(phase_Noutput), maxNinstance),source=0_pInt)
 allocate(plastic_isotropic_output(maxval(phase_Noutput), maxNinstance))
          plastic_isotropic_output = ''
 allocate(plastic_isotropic_Noutput(maxNinstance),                              source=0_pInt)

 allocate(param(maxNinstance))                                                                      ! one container of parameters per instance

 rewind(fileUnit)
 phase = 0_pInt
 do while (trim(line) /= IO_EOF .and. IO_lc(IO_getTag(line,'<','>')) /= material_partPhase)         ! wind forward to <phase>
   line = IO_read(fileUnit)
 enddo
 
 parsingFile: do while (trim(line) /= IO_EOF)                                                       ! read through sections of phase part
   line = IO_read(fileUnit)
   if (IO_isBlank(line)) cycle                                                                      ! skip empty lines
   if (IO_getTag(line,'<','>') /= '') then                                                          ! stop at next part
     line = IO_read(fileUnit, .true.)                                                               ! reset IO_read
     exit                                                                                           
   endif
   if (IO_getTag(line,'[',']') /= '') then                                                          ! next section
     phase = phase + 1_pInt                                                                         ! advance section counter
     if (phase_plasticity(phase) == PLASTICITY_ISOTROPIC_ID) then
       p => param(phase_plasticityInstance(phase))                                                  ! shorthand pointer to parameter object of my constitutive law
       allocate(p%outputID(phase_Noutput(phase)))                                                   ! allocate space for IDs of every requested output
     endif
     cycle                                                                                          ! skip to next line
   endif
   if (phase > 0_pInt) then; if (phase_plasticity(phase) == PLASTICITY_ISOTROPIC_ID) then           ! one of my phases. Do not short-circuit here (.and. between if-statements), it's not safe in Fortran
     instance = phase_plasticityInstance(phase)                                                     ! which instance of my plasticity is present phase
     p => param(instance)
     chunkPos = IO_stringPos(line) 
     tag = IO_lc(IO_stringValue(line,chunkPos,1_pInt))                                              ! extract key

     select case(tag)
       case ('(output)')
         outputtag = IO_lc(IO_stringValue(line,chunkPos,2_pInt))
         select case(outputtag)
           case ('flowstress')
             plastic_isotropic_Noutput(instance) = plastic_isotropic_Noutput(instance) + 1_pInt
             p%outputID (plastic_isotropic_Noutput(instance)) = flowstress_ID
             plastic_isotropic_output(plastic_isotropic_Noutput(instance),instance) = outputtag
           case ('strainrate')
             plastic_isotropic_Noutput(instance) = plastic_isotropic_Noutput(instance) + 1_pInt
             p%outputID (plastic_isotropic_Noutput(instance)) = strainrate_ID
             plastic_isotropic_output(plastic_isotropic_Noutput(instance),instance) = outputtag
         end select

       case ('/dilatation/')
         p%dilatation      = .true.

       case ('tau0')
         p%tau0            = IO_floatValue(line,chunkPos,2_pInt)

       case ('gdot0')
         p%gdot0           = IO_floatValue(line,chunkPos,2_pInt)

       case ('n')
         p%n               = IO_floatValue(line,chunkPos,2_pInt)

       case ('h0')
         p%h0              = IO_floatValue(line,chunkPos,2_pInt)

       case ('h0_slope','slopelnrate')
         p%h0_slopeLnRate  = IO_floatValue(line,chunkPos,2_pInt)

       case ('tausat')
         p%tausat          = IO_floatValue(line,chunkPos,2_pInt)

       case ('tausat_sinhfita')
         p%tausat_SinhFitA = IO_floatValue(line,chunkPos,2_pInt)

       case ('tausat_sinhfitb')
         p%tausat_SinhFitB = IO_floatValue(line,chunkPos,2_pInt)

       case ('tausat_sinhfitc')
         p%tausat_SinhFitC = IO_floatValue(line,chunkPos,2_pInt)

       case ('tausat_sinhfitd')
         p%tausat_SinhFitD = IO_floatValue(line,chunkPos,2_pInt)

       case ('a', 'w0')
         p%a               = IO_floatValue(line,chunkPos,2_pInt)

       case ('taylorfactor')
         p%fTaylor         = IO_floatValue(line,chunkPos,2_pInt)

       case ('atol_flowstress')
         p%aTolFlowstress  = IO_floatValue(line,chunkPos,2_pInt)

       case ('atol_shear')
         p%aTolShear       = IO_floatValue(line,chunkPos,2_pInt)

       case default

     end select
   endif; endif
 enddo parsingFile

 allocate(state(maxNinstance))                                                                      ! internal state aliases
 allocate(dotState(maxNinstance))

 initializeInstances: do phase = 1_pInt, size(phase_plasticity)                                     ! loop over every plasticity
   myPhase: if (phase_plasticity(phase) == PLASTICITY_isotropic_ID) then                            ! isolate instances of own constitutive description
     NipcMyPhase = count(material_phase == phase)                                                   ! number of own material points (including point components ipc)
     instance = phase_plasticityInstance(phase)
     p => param(instance)
     extmsg = ''
!--------------------------------------------------------------------------------------------------
!  sanity checks
     if (p%aTolShear        <= 0.0_pReal) p%aTolShear = 1.0e-6_pReal    ! default absolute tolerance 1e-6
     if (p%tau0              < 0.0_pReal) extmsg = trim(extmsg)//' tau0'
     if (p%gdot0            <= 0.0_pReal) extmsg = trim(extmsg)//' gdot0'
     if (p%n                <= 0.0_pReal) extmsg = trim(extmsg)//' n'
     if (p%tausat           <= 0.0_pReal) extmsg = trim(extmsg)//' tausat'
     if (p%a                <= 0.0_pReal) extmsg = trim(extmsg)//' a' 
     if (p%fTaylor          <= 0.0_pReal) extmsg = trim(extmsg)//' taylorfactor'
     if (p%aTolFlowstress   <= 0.0_pReal) extmsg = trim(extmsg)//' atol_flowstress'
     if (extmsg /= '') then 
       extmsg = trim(extmsg)//' ('//PLASTICITY_ISOTROPIC_label//')'                                 ! prepare error message identifier
       call IO_error(211_pInt,ip=instance,ext_msg=extmsg)
     endif
!--------------------------------------------------------------------------------------------------
!  Determine size of postResults array
     outputsLoop: do o = 1_pInt,plastic_isotropic_Noutput(instance)
       select case(p%outputID(o))
         case(flowstress_ID,strainrate_ID)
           mySize = 1_pInt
         case default
       end select
  
       outputFound: if (mySize > 0_pInt) then
         plastic_isotropic_sizePostResult(o,instance) = mySize
         plastic_isotropic_sizePostResults(instance) = &
         plastic_isotropic_sizePostResults(instance) + mySize
       endif outputFound
     enddo outputsLoop

!--------------------------------------------------------------------------------------------------
! allocate state arrays
     sizeDotState   = 2_pInt                                                                         ! flowstress, accumulated_shear
     sizeDeltaState = 0_pInt                                                                         ! no sudden jumps in state
     sizeState      = sizeDotState + sizeDeltaState
     plasticState(phase)%sizeState = sizeState
     plasticState(phase)%sizeDotState = sizeDotState
     plasticState(phase)%sizeDeltaState = sizeDeltaState
     plasticState(phase)%sizePostResults = plastic_isotropic_sizePostResults(instance)
     plasticState(phase)%nSlip = 1
     plasticState(phase)%nTwin = 0
     plasticState(phase)%nTrans= 0
     allocate(plasticState(phase)%aTolState          (   sizeState))

     allocate(plasticState(phase)%state0             (   sizeState,NipcMyPhase),source=0.0_pReal)

     allocate(plasticState(phase)%partionedState0    (   sizeState,NipcMyPhase),source=0.0_pReal)
     allocate(plasticState(phase)%subState0          (   sizeState,NipcMyPhase),source=0.0_pReal)
     allocate(plasticState(phase)%state              (   sizeState,NipcMyPhase),source=0.0_pReal)
     allocate(plasticState(phase)%dotState           (sizeDotState,NipcMyPhase),source=0.0_pReal)
     allocate(plasticState(phase)%deltaState       (sizeDeltaState,NipcMyPhase),source=0.0_pReal)
     if (any(numerics_integrator == 1_pInt)) then
       allocate(plasticState(phase)%previousDotState (sizeDotState,NipcMyPhase),source=0.0_pReal)
       allocate(plasticState(phase)%previousDotState2(sizeDotState,NipcMyPhase),source=0.0_pReal)
     endif
     if (any(numerics_integrator == 4_pInt)) &
       allocate(plasticState(phase)%RK4dotState      (sizeDotState,NipcMyPhase),source=0.0_pReal)
     if (any(numerics_integrator == 5_pInt)) &
       allocate(plasticState(phase)%RKCK45dotState (6,sizeDotState,NipcMyPhase),source=0.0_pReal)

!--------------------------------------------------------------------------------------------------
! locally defined state aliases and initialization of state0 and aTolState

     state(instance)%flowstress             => plasticState(phase)%state    (1,1:NipcMyPhase)
     dotState(instance)%flowstress          => plasticState(phase)%dotState (1,1:NipcMyPhase)
     plasticState(phase)%state0(1,1:NipcMyPhase) = p%tau0
     plasticState(phase)%aTolState(1)       =  p%aTolFlowstress

     state(instance)%accumulatedShear       => plasticState(phase)%state    (2,1:NipcMyPhase)
     dotState(instance)%accumulatedShear    => plasticState(phase)%dotState (2,1:NipcMyPhase)
     plasticState(phase)%state0 (2,1:NipcMyPhase) = 0.0_pReal
     plasticState(phase)%aTolState(2)       =  p%aTolShear
     ! global alias
     plasticState(phase)%slipRate           => plasticState(phase)%dotState(2:2,1:NipcMyPhase)
     plasticState(phase)%accumulatedSlip    => plasticState(phase)%state   (2:2,1:NipcMyPhase)

   endif myPhase
 enddo initializeInstances

end subroutine plastic_isotropic_init

!--------------------------------------------------------------------------------------------------
!> @brief calculates plastic velocity gradient and its tangent
!--------------------------------------------------------------------------------------------------
subroutine plastic_isotropic_LpAndItsTangent(Lp,dLp_dTstar99,Tstar_v,ipc,ip,el)
 use debug, only: &
   debug_level, &
   debug_constitutive, &
   debug_levelBasic, &
   debug_levelExtensive, &
   debug_levelSelective, &
   debug_e, &
   debug_i, &
   debug_g
 use math, only: &
   math_mul6x6, &
   math_Mandel6to33, &
   math_Plain3333to99, &
   math_deviatoric33, &
   math_mul33xx33, &
   math_transpose33
 use material, only: &
   phasememberAt, &
   material_phase, &
   phase_plasticityInstance

 implicit none
 real(pReal), dimension(3,3), intent(out) :: &
   Lp                                                                                               !< plastic velocity gradient
 real(pReal), dimension(9,9), intent(out) :: &
   dLp_dTstar99                                                                                     !< derivative of Lp with respect to 2nd Piola Kirchhoff stress

 real(pReal), dimension(6),   intent(in) :: &
   Tstar_v                                                                                          !< 2nd Piola Kirchhoff stress tensor in Mandel notation
 integer(pInt),               intent(in) :: &
   ipc, &                                                                                           !< component-ID of integration point
   ip, &                                                                                            !< integration point
   el                                                                                               !< element

 type(tParameters), pointer :: p
 
 real(pReal), dimension(3,3) :: &
   Tstar_dev_33                                                                                     !< deviatoric part of the 2nd Piola Kirchhoff stress tensor as 2nd order tensor
 real(pReal), dimension(3,3,3,3) :: &
   dLp_dTstar_3333                                                                                  !< derivative of Lp with respect to Tstar as 4th order tensor
 real(pReal) :: &
   gamma_dot, &                                                                                     !< strainrate
   norm_Tstar_dev, &                                                                                !< euclidean norm of Tstar_dev
   squarenorm_Tstar_dev                                                                             !< square of the euclidean norm of Tstar_dev
 integer(pInt) :: &
   instance, of, &
   k, l, m, n

 of = phasememberAt(ipc,ip,el)                                                                      ! phasememberAt should be tackled by material and be renamed to material_phasemember
 instance = phase_plasticityInstance(material_phase(ipc,ip,el))
 p => param(instance)
 
 Tstar_dev_33 = math_deviatoric33(math_Mandel6to33(Tstar_v))                                        ! deviatoric part of 2nd Piola-Kirchhoff stress
 squarenorm_Tstar_dev = math_mul33xx33(Tstar_dev_33,Tstar_dev_33)
 norm_Tstar_dev = sqrt(squarenorm_Tstar_dev) 

 if (norm_Tstar_dev <= 0.0_pReal) then                                                              ! Tstar == 0 --> both Lp and dLp_dTstar are zero
   Lp = 0.0_pReal
   dLp_dTstar99 = 0.0_pReal
 else
   gamma_dot = p%gdot0 &
             * ( sqrt(1.5_pReal) * norm_Tstar_dev / p%fTaylor / state(instance)%flowstress(of) ) &
             **p%n

   Lp = Tstar_dev_33/norm_Tstar_dev * gamma_dot/p%fTaylor 

   if (iand(debug_level(debug_constitutive), debug_levelExtensive) /= 0_pInt &
       .and. ((el == debug_e .and. ip == debug_i .and. ipc == debug_g) &
              .or. .not. iand(debug_level(debug_constitutive),debug_levelSelective) /= 0_pInt)) then
     write(6,'(a,i8,1x,i2,1x,i3)') '<< CONST isotropic >> at el ip g ',el,ip,ipc
     write(6,'(/,a,/,3(12x,3(f12.4,1x)/))') '<< CONST isotropic >> Tstar (dev) / MPa', &
                                      math_transpose33(Tstar_dev_33(1:3,1:3))*1.0e-6_pReal
     write(6,'(/,a,/,f12.5)') '<< CONST isotropic >> norm Tstar / MPa', norm_Tstar_dev*1.0e-6_pReal
     write(6,'(/,a,/,f12.5)') '<< CONST isotropic >> gdot', gamma_dot
   end if
!--------------------------------------------------------------------------------------------------
! Calculation of the tangent of Lp
   forall (k=1_pInt:3_pInt,l=1_pInt:3_pInt,m=1_pInt:3_pInt,n=1_pInt:3_pInt) &
     dLp_dTstar_3333(k,l,m,n) = (p%n-1.0_pReal) * &
                                      Tstar_dev_33(k,l)*Tstar_dev_33(m,n) / squarenorm_Tstar_dev
   forall (k=1_pInt:3_pInt,l=1_pInt:3_pInt) &
     dLp_dTstar_3333(k,l,k,l) = dLp_dTstar_3333(k,l,k,l) + 1.0_pReal
   forall (k=1_pInt:3_pInt,m=1_pInt:3_pInt) &
     dLp_dTstar_3333(k,k,m,m) = dLp_dTstar_3333(k,k,m,m) - 1.0_pReal/3.0_pReal
   dLp_dTstar99 = math_Plain3333to99(gamma_dot / p%fTaylor * &
                                      dLp_dTstar_3333 / norm_Tstar_dev)
 end if
end subroutine plastic_isotropic_LpAndItsTangent

!--------------------------------------------------------------------------------------------------
!> @brief calculates plastic velocity gradient and its tangent
!--------------------------------------------------------------------------------------------------
subroutine plastic_isotropic_LiAndItsTangent(Li,dLi_dTstar_3333,Tstar_v,ipc,ip,el)
 use math, only: &
   math_mul6x6, &
   math_Mandel6to33, &
   math_Plain3333to99, &
   math_spherical33, &
   math_mul33xx33
 use material, only: &
   phasememberAt, &
   material_phase, &
   phase_plasticityInstance

 implicit none
 real(pReal), dimension(3,3), intent(out) :: &
   Li                                                                                               !< plastic velocity gradient
 real(pReal), dimension(3,3,3,3), intent(out)  :: &
   dLi_dTstar_3333                                                                                  !< derivative of Li with respect to Tstar as 4th order tensor
 real(pReal), dimension(6),   intent(in) :: &
   Tstar_v                                                                                          !< 2nd Piola Kirchhoff stress tensor in Mandel notation
 integer(pInt),               intent(in) :: &
   ipc, &                                                                                           !< component-ID of integration point
   ip, &                                                                                            !< integration point
   el                                                                                               !< element

 type(tParameters), pointer :: p
 
 real(pReal), dimension(3,3) :: &
   Tstar_sph_33                                                                                     !< sphiatoric part of the 2nd Piola Kirchhoff stress tensor as 2nd order tensor
 real(pReal) :: &
   gamma_dot, &                                                                                     !< strainrate
   norm_Tstar_sph, &                                                                                !< euclidean norm of Tstar_sph
   squarenorm_Tstar_sph                                                                             !< square of the euclidean norm of Tstar_sph
 integer(pInt) :: &
   instance, of, &
   k, l, m, n

 of = phasememberAt(ipc,ip,el)                                                                      ! phasememberAt should be tackled by material and be renamed to material_phasemember
 instance = phase_plasticityInstance(material_phase(ipc,ip,el))
 p => param(instance)
 
 Tstar_sph_33 = math_spherical33(math_Mandel6to33(Tstar_v))                                         ! spherical part of 2nd Piola-Kirchhoff stress
 squarenorm_Tstar_sph = math_mul33xx33(Tstar_sph_33,Tstar_sph_33)
 norm_Tstar_sph = sqrt(squarenorm_Tstar_sph) 

 if (p%dilatation .and. norm_Tstar_sph > 0.0_pReal) then                              ! Tstar == 0 or J2 plascitiy --> both Li and dLi_dTstar are zero
   gamma_dot = p%gdot0 &
               * (sqrt(1.5_pReal) * norm_Tstar_sph / p%fTaylor / state(instance)%flowstress(of) ) &
               **p%n

   Li = Tstar_sph_33/norm_Tstar_sph * gamma_dot/p%fTaylor

   !--------------------------------------------------------------------------------------------------
   ! Calculation of the tangent of Li
   forall (k=1_pInt:3_pInt,l=1_pInt:3_pInt,m=1_pInt:3_pInt,n=1_pInt:3_pInt) &
     dLi_dTstar_3333(k,l,m,n) = (p%n-1.0_pReal) * &
                                      Tstar_sph_33(k,l)*Tstar_sph_33(m,n) / squarenorm_Tstar_sph
   forall (k=1_pInt:3_pInt,l=1_pInt:3_pInt) &
     dLi_dTstar_3333(k,l,k,l) = dLi_dTstar_3333(k,l,k,l) + 1.0_pReal

   dLi_dTstar_3333 = gamma_dot / p%fTaylor * &
                                      dLi_dTstar_3333 / norm_Tstar_sph
 else
  Li = 0.0_pReal
  dLi_dTstar_3333 = 0.0_pReal
 endif
 end subroutine plastic_isotropic_LiAndItsTangent


!--------------------------------------------------------------------------------------------------
!> @brief calculates the rate of change of microstructure
!--------------------------------------------------------------------------------------------------
subroutine plastic_isotropic_dotState(Tstar_v,ipc,ip,el)
 use prec, only: &
   dEq0
 use math, only: &
   math_mul6x6
 use material, only: &
   phasememberAt, &
   material_phase, &
   phase_plasticityInstance
 
 implicit none
 real(pReal), dimension(6), intent(in):: &
   Tstar_v                                                                                          !< 2nd Piola Kirchhoff stress tensor in Mandel notation
 integer(pInt),             intent(in) :: &
   ipc, &                                                                                           !< component-ID of integration point
   ip, &                                                                                            !< integration point
   el                                                                                               !< element
 type(tParameters), pointer :: p
 real(pReal), dimension(6) :: &
   Tstar_dev_v                                                                                      !< deviatoric 2nd Piola Kirchhoff stress tensor in Mandel notation
 real(pReal) :: &
   gamma_dot, &                                                                                     !< strainrate
   hardening, &                                                                                     !< hardening coefficient
   saturation, &                                                                                    !< saturation flowstress
   norm_Tstar_v                                                                                     !< euclidean norm of Tstar_dev
 integer(pInt) :: &
   instance, &                                                                                      !< instance of my instance (unique number of my constitutive model)
   of                                                                                               !< shortcut notation for offset position in state array

 of = phasememberAt(ipc,ip,el)                                                                      ! phasememberAt should be tackled by material and be renamed to material_phasemember
 instance = phase_plasticityInstance(material_phase(ipc,ip,el))
 p => param(instance)
 
!--------------------------------------------------------------------------------------------------
! norm of (deviatoric) 2nd Piola-Kirchhoff stress
 if (p%dilatation) then
   norm_Tstar_v = sqrt(math_mul6x6(Tstar_v,Tstar_v))
 else
   Tstar_dev_v(1:3) = Tstar_v(1:3) - sum(Tstar_v(1:3))/3.0_pReal
   Tstar_dev_v(4:6) = Tstar_v(4:6)
   norm_Tstar_v = sqrt(math_mul6x6(Tstar_dev_v,Tstar_dev_v))
 end if
!--------------------------------------------------------------------------------------------------
! strain rate 
 gamma_dot = p%gdot0 * ( sqrt(1.5_pReal) * norm_Tstar_v & 
            / &!-----------------------------------------------------------------------------------
           (p%fTaylor*state(instance)%flowstress(of) ))**p%n
 
!--------------------------------------------------------------------------------------------------
! hardening coefficient
 if (abs(gamma_dot) > 1e-12_pReal) then
   if (dEq0(p%tausat_SinhFitA)) then
     saturation = p%tausat
   else
     saturation = p%tausat &
                + asinh( (gamma_dot / p%tausat_SinhFitA&
                         )**(1.0_pReal / p%tausat_SinhFitD)&
                       )**(1.0_pReal / p%tausat_SinhFitC) &
                   / ( p%tausat_SinhFitB &
                       * (gamma_dot / p%gdot0)**(1.0_pReal / p%n) &
                     )
   endif
   hardening = ( p%h0 + p%h0_slopeLnRate * log(gamma_dot) ) &
               * abs( 1.0_pReal - state(instance)%flowstress(of)/saturation )**p%a &
               * sign(1.0_pReal, 1.0_pReal - state(instance)%flowstress(of)/saturation)
 else
   hardening = 0.0_pReal
 endif

 dotState(instance)%flowstress      (of) = hardening * gamma_dot
 dotState(instance)%accumulatedShear(of) =             gamma_dot

end subroutine plastic_isotropic_dotState

!--------------------------------------------------------------------------------------------------
!> @brief return array of constitutive results
!--------------------------------------------------------------------------------------------------
function plastic_isotropic_postResults(Tstar_v,ipc,ip,el)
 use math, only: &
   math_mul6x6
 use material, only: &
   material_phase, &
   phasememberAt, &
   phase_plasticityInstance

 implicit none
 real(pReal), dimension(6),  intent(in) :: &
   Tstar_v                                                                                          !< 2nd Piola Kirchhoff stress tensor in Mandel notation
 integer(pInt),              intent(in) :: &
   ipc, &                                                                                           !< component-ID of integration point
   ip, &                                                                                            !< integration point
   el                                                                                               !< element

 type(tParameters), pointer :: p
 
 real(pReal), dimension(plastic_isotropic_sizePostResults(phase_plasticityInstance(material_phase(ipc,ip,el)))) :: &
                                           plastic_isotropic_postResults

 real(pReal), dimension(6) :: &
   Tstar_dev_v                                                                                      !< deviatoric 2nd Piola Kirchhoff stress tensor in Mandel notation
 real(pReal) :: &
   norm_Tstar_v                                                                                     ! euclidean norm of Tstar_dev
 integer(pInt) :: &
   instance, &                                                                                      !< instance of my instance (unique number of my constitutive model)
   of, &                                                                                            !< shortcut notation for offset position in state array
   c, &
   o

 of = phasememberAt(ipc,ip,el)                                                                      ! phasememberAt should be tackled by material and be renamed to material_phasemember
 instance = phase_plasticityInstance(material_phase(ipc,ip,el))
 p => param(instance)
 
!--------------------------------------------------------------------------------------------------
! norm of (deviatoric) 2nd Piola-Kirchhoff stress
 if (p%dilatation) then
   norm_Tstar_v = sqrt(math_mul6x6(Tstar_v,Tstar_v))
 else
   Tstar_dev_v(1:3) = Tstar_v(1:3) - sum(Tstar_v(1:3))/3.0_pReal
   Tstar_dev_v(4:6) = Tstar_v(4:6)
   norm_Tstar_v = sqrt(math_mul6x6(Tstar_dev_v,Tstar_dev_v))
 end if
 
 c = 0_pInt
 plastic_isotropic_postResults = 0.0_pReal

 outputsLoop: do o = 1_pInt,plastic_isotropic_Noutput(instance)
   select case(p%outputID(o))
     case (flowstress_ID)
       plastic_isotropic_postResults(c+1_pInt) = state(instance)%flowstress(of)
       c = c + 1_pInt
     case (strainrate_ID)
       plastic_isotropic_postResults(c+1_pInt) = &
                p%gdot0 * (            sqrt(1.5_pReal) * norm_Tstar_v & 
             / &!----------------------------------------------------------------------------------
              (p%fTaylor * state(instance)%flowstress(of)) ) ** p%n
       c = c + 1_pInt
   end select
 enddo outputsLoop

end function plastic_isotropic_postResults


end module plastic_isotropic
