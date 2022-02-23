!--------------------------------------------------------------------------------------------------
!> @author Martin Diehl, KU Leuven
!> @brief Dummy homogenization scheme for 1 constituent per material point
!--------------------------------------------------------------------------------------------------
submodule(homogenization:thermal) thermal_pass

contains

module subroutine pass_init()

  print'(/,1x,a)', '<<<+-  homogenization:thermal:pass init  -+>>>'

  if (homogenization_Nconstituents(1) /= 1) & !ToDo: needs extension to multiple homogenizations
    call IO_error(211,ext_msg='(pass) with N_constituents !=1')

end subroutine pass_init

end submodule thermal_pass
