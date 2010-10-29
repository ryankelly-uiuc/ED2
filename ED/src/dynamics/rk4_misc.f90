!==========================================================================================!
!==========================================================================================!
!    This subroutine copies that variables that are integrated by the Runge-Kutta solver   !
! to a buffer structure.                                                                   !
!------------------------------------------------------------------------------------------!
subroutine copy_patch_init(sourcesite,ipa,targetp)
   use ed_state_vars        , only : sitetype               & ! structure
                                   , patchtype              ! ! structure
   use grid_coms            , only : nzg                    & ! intent(in)
                                   , nzs                    ! ! intent(in) 
   use ed_misc_coms         , only : fast_diagnostics       ! ! intent(in)
   use consts_coms          , only : cpi8                   & ! intent(in)
                                   , ep8                    & ! intent(in)
                                   , cp8                    & ! intent(in)
                                   , epim18                 & ! intent(in)
                                   , alvl8                  & ! intent(in)
                                   , rdry8                  & ! intent(in)
                                   , rdryi8                 & ! intent(in)
                                   , p00i8                  & ! intent(in)
                                   , rocp8                  ! ! intent(in)
   use rk4_coms             , only : rk4patchtype           & ! structure
                                   , rk4site                & ! structure
                                   , hcapveg_ref            & ! intent(in)
                                   , rk4eps                 & ! intent(in)
                                   , min_height             & ! intent(in)
                                   , any_solvable           & ! intent(out)
                                   , zoveg                  & ! intent(out)
                                   , zveg                   & ! intent(out)
                                   , wcapcan                & ! intent(out)
                                   , wcapcani               & ! intent(out)
                                   , rk4water_stab_thresh   & ! intent(in)
                                   , rk4tiny_sfcw_mass      & ! intent(in)
                                   , checkbudget            & ! intent(in)
                                   , print_detailed         & ! intent(in)
                                   , find_derived_thbounds  & ! sub-routine
                                   , reset_rk4_fluxes       ! ! sub-routine
   use ed_max_dims          , only : n_pft                  ! ! intent(in)
   use canopy_radiation_coms, only : tai_min                ! ! intent(in)
   use therm_lib8           , only : qwtk8                  & ! subroutine
                                   , thetaeiv8              & ! function
                                   , idealdenssh8           & ! function
                                   , rehuil8                & ! function
                                   , rslif8                 & ! function
                                   , reducedpress8          ! ! function
   use allometry            , only : dbh2bl                 ! ! function
   use soil_coms            , only : soil8                  ! ! intent(in)
   implicit none

   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype)    , target     :: targetp
   type(sitetype)        , target     :: sourcesite
   integer               , intent(in) :: ipa
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)       , pointer    :: cpatch
   real(kind=8)                       :: hvegpat_min
   real(kind=8)                       :: hcap_scale
   real(kind=8)                       :: rsat
   integer                            :: ico
   integer                            :: ipft
   integer                            :: k
   !---------------------------------------------------------------------------------------!

   !---------------------------------------------------------------------------------------!
   !     Between time steps the pressure may change because of change in atmospheric       !
   ! pressure, which means that temperature is not conserved.  Potential temperature and   !
   ! equivalent potential temperature, on the other hand, are conserved because there is   !
   ! no heat flux between time steps.  So we use these instead to start all other vari-    !
   ! ables.                                                                                !
   !---------------------------------------------------------------------------------------!
   !----- 1. Update thermo variables that are conserved between steps. --------------------!
   targetp%can_theta    = dble(sourcesite%can_theta(ipa))
   targetp%can_theiv    = dble(sourcesite%can_theiv(ipa))
   targetp%can_shv      = dble(sourcesite%can_shv(ipa))
   targetp%can_co2      = dble(sourcesite%can_co2(ipa))
   targetp%can_depth    = dble(sourcesite%can_depth(ipa))
   targetp%can_rvap     = targetp%can_shv / (1.d0 - targetp%can_shv)

   !----- 2. Update the canopy pressure and Exner function. -------------------------------!
   targetp%can_prss     = reducedpress8(rk4site%atm_prss,rk4site%atm_theta,rk4site%atm_shv &
                                       ,rk4site%geoht,targetp%can_theta,targetp%can_shv    &
                                       ,targetp%can_depth)
   targetp%can_exner    = cp8 * (targetp%can_prss * p00i8) ** rocp8

   !---------------------------------------------------------------------------------------!
   !  3. Update the natural logarithm of theta_eiv, temperature, density, relative         !
   !     humidity, and the saturation specific humidity.                                   !
   !---------------------------------------------------------------------------------------!
   targetp%can_lntheta  = log(targetp%can_theta)
   targetp%can_temp     = cpi8 * targetp%can_theta * targetp%can_exner
   targetp%can_rhos     = idealdenssh8(targetp%can_prss,targetp%can_temp,targetp%can_shv)
   targetp%can_rhv      = rehuil8(targetp%can_prss,targetp%can_temp,targetp%can_rvap)
   rsat                 = rslif8(targetp%can_prss,targetp%can_temp)
   targetp%can_ssh      = rsat / (1.d0 + rsat)
   !---------------------------------------------------------------------------------------!

   !----- 4. Find the lower and upper bounds for the derived properties. ------------------!
   call find_derived_thbounds(rk4site%lsl,nzg,targetp%can_rhos,targetp%can_theta           &
                             ,targetp%can_temp,targetp%can_shv,targetp%can_rvap            &
                             ,targetp%can_prss,targetp%can_depth                           &
                             ,sourcesite%ntext_soil(:,ipa))

   !----- Impose a non-sense number for flag_wflxgc. --------------------------------------!
   targetp%flag_wflxgc  = -1

   do k = rk4site%lsl, nzg
      targetp%soil_water(k)   = dble(sourcesite%soil_water(k,ipa))
      targetp%soil_energy(k)  = dble(sourcesite%soil_energy(k,ipa))
      targetp%soil_tempk(k)   = dble(sourcesite%soil_tempk(k,ipa))
      targetp%soil_fracliq(k) = dble(sourcesite%soil_fracliq(k,ipa))
   end do

   do k = 1, nzs
      targetp%sfcwater_mass(k)    = dble(sourcesite%sfcwater_mass(k,ipa))
      targetp%sfcwater_depth(k)   = dble(sourcesite%sfcwater_depth(k,ipa))
      !----- Converting sfcwater_energy to J/m� inside the Runge-Kutta integrator. --------!
      targetp%sfcwater_energy(k)  = dble(sourcesite%sfcwater_energy(k,ipa))                &
                                  * dble(sourcesite%sfcwater_mass(k,ipa))
      targetp%sfcwater_tempk(k)   = dble(sourcesite%sfcwater_tempk(k,ipa))
      targetp%sfcwater_fracliq(k) = dble(sourcesite%sfcwater_fracliq(k,ipa))
   end do

   targetp%ustar         = dble(sourcesite%ustar (ipa))
   targetp%cstar         = dble(sourcesite%cstar (ipa))
   targetp%tstar         = dble(sourcesite%tstar (ipa))
   targetp%qstar         = dble(sourcesite%qstar (ipa))
   targetp%estar         = 0.d0

   targetp%zeta          = dble(sourcesite%zeta  (ipa))
   targetp%ribulk        = dble(sourcesite%ribulk(ipa))

   targetp%upwp          = dble(sourcesite%upwp  (ipa))
   targetp%wpwp          = dble(sourcesite%wpwp  (ipa))
   targetp%tpwp          = dble(sourcesite%tpwp  (ipa))
   targetp%qpwp          = dble(sourcesite%qpwp  (ipa))
   targetp%cpwp          = dble(sourcesite%cpwp  (ipa))

  
   targetp%nlev_sfcwater = sourcesite%nlev_sfcwater(ipa)


   !----- The virtual pools should be always zero, they are temporary entities ------------!
   targetp%virtual_water = 0.0d0
   targetp%virtual_heat  = 0.0d0
   targetp%virtual_depth = 0.0d0

   if (targetp%nlev_sfcwater == 0) then
      targetp%virtual_flag = 2
   else
      if (targetp%sfcwater_mass(1) < rk4tiny_sfcw_mass) then
         targetp%virtual_flag = 2
      elseif (targetp%sfcwater_mass(1) < rk4water_stab_thresh) then
         targetp%virtual_flag = 1
      else
         targetp%virtual_flag = 0
      end if
   end if

   !---------------------------------------------------------------------------------------!
   !     Here we find the minimum patch-level leaf heat capacity.  If the total patch leaf !
   ! heat capacity is less than this, we scale the cohorts heat capacity inside the        !
   ! integrator, so it preserves the proportional heat capacity and prevents the pool to   !
   ! be too small.                                                                         !
   !---------------------------------------------------------------------------------------!
   cpatch => sourcesite%patch(ipa)
   sourcesite%hcapveg(ipa) = 0.
   sourcesite%lai(ipa)     = 0.
   sourcesite%wpa(ipa)     = 0.
   sourcesite%wai(ipa)     = 0.
   do ico=1,cpatch%ncohorts
      sourcesite%hcapveg(ipa) = sourcesite%hcapveg(ipa) + cpatch%hcapveg(ico)
      sourcesite%lai(ipa)     = sourcesite%lai(ipa)     + cpatch%lai(ico)
      sourcesite%wpa(ipa)     = sourcesite%wpa(ipa)     + cpatch%wpa(ico)
      sourcesite%wai(ipa)     = sourcesite%wai(ipa)     + cpatch%wai(ico)
   end do
   
   any_solvable = .false.
   do ico=1, cpatch%ncohorts
      !----- Copying the flag that determines whether this cohort is numerically stable. --!
      targetp%solvable(ico) = cpatch%solvable(ico)
      if (targetp%solvable(ico)) any_solvable = .true.
   end do

   if ((sourcesite%lai(ipa)+sourcesite%wai(ipa)) > tai_min) then
      hvegpat_min = hcapveg_ref * max(dble(cpatch%hite(1)),min_height)
      hcap_scale  = max(1.d0,hvegpat_min / sourcesite%hcapveg(ipa))
   else
      hcap_scale  = 1.d0
   end if

   do ico = 1,cpatch%ncohorts
      ipft=cpatch%pft(ico)
      !----- Copy the leaf area index and total (leaf+branch+twig) area index. ------------!
      targetp%lai(ico)    = dble(cpatch%lai(ico))
      targetp%wai(ico)    = dble(cpatch%wai(ico))
      targetp%wpa(ico)    = dble(cpatch%wpa(ico))
      targetp%tai(ico)    = targetp%lai(ico) + dble(cpatch%wai(ico))

      !------------------------------------------------------------------------------------!
      !    If the cohort is too small, we give some extra heat capacity, so the model can  !
      ! run in a stable range inside the integrator.  At the end this extra heat capacity  !
      ! will be removed.                                                                   !
      !------------------------------------------------------------------------------------!
      targetp%hcapveg(ico) = dble(cpatch%hcapveg(ico)) * hcap_scale

      !------------------------------------------------------------------------------------!
      !     Checking whether this is considered a "safe" one or not.  In case it is, we    !
      ! copy water, temperature, and liquid fraction, and scale energy and heat capacity   !
      ! as needed.  Otherwise, just fill with some safe values, but the cohort won't be    !
      ! really solved.                                                                     !
      !------------------------------------------------------------------------------------!
      targetp%veg_water(ico)     = dble(cpatch%veg_water(ico))

      if (targetp%solvable(ico)) then
         targetp%veg_energy(ico)    = dble(cpatch%veg_energy(ico))                         &
                                    + (targetp%hcapveg(ico)-dble(cpatch%hcapveg(ico)))     &
                                    * dble(cpatch%veg_temp(ico))
         call qwtk8(targetp%veg_energy(ico),targetp%veg_water(ico),targetp%hcapveg(ico)    &
                   ,targetp%veg_temp(ico),targetp%veg_fliq(ico))
      else
         targetp%veg_fliq(ico)   = dble(cpatch%veg_fliq(ico))
         targetp%veg_temp(ico)   = dble(cpatch%veg_temp(ico))
         targetp%veg_energy(ico) = targetp%hcapveg(ico) * targetp%veg_temp(ico)
      end if
   end do

   !----- Diagnostics variables -----------------------------------------------------------!
   if(fast_diagnostics) then
      !----------------------------------------------------------------------!
      !   N.B. The "budget" variables are not copied here because they are   !
      ! integrated outside RK4.  Inside RK4 we only want the contribution    !
      ! of those variables during the span of one time step.                 !
      !----------------------------------------------------------------------!
      targetp%avg_carbon_ac      = dble(sourcesite%avg_carbon_ac(ipa)     )
      targetp%avg_vapor_vc       = dble(sourcesite%avg_vapor_vc(ipa)      )
      targetp%avg_dew_cg         = dble(sourcesite%avg_dew_cg(ipa)        )
      targetp%avg_vapor_gc       = dble(sourcesite%avg_vapor_gc(ipa)      )
      targetp%avg_wshed_vg       = dble(sourcesite%avg_wshed_vg(ipa)      )
      targetp%avg_intercepted    = dble(sourcesite%avg_intercepted(ipa)   )
      targetp%avg_throughfall    = dble(sourcesite%avg_throughfall(ipa)   )
      targetp%avg_vapor_ac       = dble(sourcesite%avg_vapor_ac(ipa)      )
      targetp%avg_transp         = dble(sourcesite%avg_transp(ipa)        )
      targetp%avg_evap           = dble(sourcesite%avg_evap(ipa)          )
      targetp%avg_drainage       = dble(sourcesite%avg_drainage(ipa)      )
      targetp%avg_drainage_heat  = dble(sourcesite%avg_drainage_heat(ipa) )
      targetp%avg_netrad         = dble(sourcesite%avg_netrad(ipa)        )
      targetp%avg_sensible_vc    = dble(sourcesite%avg_sensible_vc(ipa)   )
      targetp%avg_qwshed_vg      = dble(sourcesite%avg_qwshed_vg(ipa)     )
      targetp%avg_qintercepted   = dble(sourcesite%avg_qintercepted(ipa)  )
      targetp%avg_qthroughfall   = dble(sourcesite%avg_qthroughfall(ipa)  )
      targetp%avg_sensible_gc    = dble(sourcesite%avg_sensible_gc(ipa)   )
      targetp%avg_sensible_ac    = dble(sourcesite%avg_sensible_ac(ipa)   )

      do k = rk4site%lsl, nzg
         targetp%avg_sensible_gg(k) = dble(sourcesite%avg_sensible_gg(k,ipa))
         targetp%avg_smoist_gg(k)   = dble(sourcesite%avg_smoist_gg(k,ipa)  )
         targetp%avg_smoist_gc(k)   = dble(sourcesite%avg_smoist_gc(k,ipa)  )
      end do
   end if
   if (checkbudget) then
      targetp%co2budget_storage     = dble(sourcesite%co2budget_initialstorage(ipa))
      targetp%ebudget_storage       = dble(sourcesite%ebudget_initialstorage(ipa))
      targetp%wbudget_storage       = dble(sourcesite%wbudget_initialstorage(ipa))
      targetp%co2budget_loss2atm    = 0.d0
      targetp%ebudget_loss2atm      = 0.d0
      targetp%ebudget_loss2drainage = 0.d0
      targetp%ebudget_loss2runoff   = 0.d0
      targetp%wbudget_loss2atm      = 0.d0
      targetp%wbudget_loss2drainage = 0.d0
      targetp%wbudget_loss2runoff   = 0.d0
   end if

   if (print_detailed) call reset_rk4_fluxes(targetp)

   return
end subroutine copy_patch_init
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutine copies the carbon fluxes, which could not be copied by the time we    !
! called copy_patch_init.                                                                  !
!------------------------------------------------------------------------------------------!
subroutine copy_patch_init_carbon(sourcesite,ipa,targetp)
   use ed_state_vars        , only : sitetype              & ! structure
                                   , patchtype             ! ! structure
   use consts_coms          , only : day_sec8              & ! intent(in)
                                   , umol_2_kgC8           ! ! intent(in)
   use rk4_coms             , only : rk4patchtype          ! ! structure
   implicit none

   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype)    , target     :: targetp
   type(sitetype)        , target     :: sourcesite
   integer               , intent(in) :: ipa
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)       , pointer    :: cpatch
   integer                            :: ico
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !     Here we copy the cohort level variables that are part of the carbon budget.       !
   !---------------------------------------------------------------------------------------!
   cpatch => sourcesite%patch(ipa)
   do ico = 1,cpatch%ncohorts
      !----- Copy the plant density. ------------------------------------------------------!
      targetp%nplant(ico) = dble(cpatch%nplant(ico))

      !----- Copy the variables that are already in �mol/m�/s. ----------------------------!
      targetp%gpp         (ico) = dble(cpatch%gpp                (ico))
      targetp%leaf_resp   (ico) = dble(cpatch%leaf_respiration   (ico))
      targetp%root_resp   (ico) = dble(cpatch%root_respiration   (ico))

      !------------------------------------------------------------------------------------!
      !     The following variables are in kgC/plant/day, convert them to �mol/m�/s.       !
      !------------------------------------------------------------------------------------!
      targetp%growth_resp (ico) = dble(cpatch%growth_respiration (ico))                    &
                                * targetp%nplant(ico) / (day_sec8 * umol_2_kgC8)
      targetp%storage_resp(ico) = dble(cpatch%storage_respiration(ico))                    &
                                * targetp%nplant(ico) / (day_sec8 * umol_2_kgC8)
      targetp%vleaf_resp  (ico) = dble(cpatch%vleaf_respiration  (ico))                    &
                                * targetp%nplant(ico) / (day_sec8 * umol_2_kgC8)
   end do

   !----- Heterotrophic respiration terms. ------------------------------------------------!
   targetp%cwd_rh = dble(sourcesite%cwd_rh(ipa))
   targetp%rh     = dble(sourcesite%rh    (ipa))

   return
end subroutine copy_patch_init_carbon
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This function simply checks whether the relative error is large or not.               !
!------------------------------------------------------------------------------------------!
logical function large_error(err,scal)
   use rk4_coms , only : rk4eps ! intent(in)
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   real(kind=8), intent(in) :: err  ! Absolute error
   real(kind=8), intent(in) :: scal ! Characteristic scale
   !---------------------------------------------------------------------------------------!
   if(scal > 0.d0) then
      large_error = abs(err/scal)/rk4eps > 1.d0
   else
      large_error = .false.
   end if
   return
end function large_error
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This subroutine is called before the sanity check, and updates the diagnostic vari-  !
! ables, namely the temperature and liquid fraction of leaf water, soil layers and         !
! temporary snow/pond layers.                                                                      !
!------------------------------------------------------------------------------------------!
subroutine update_diagnostic_vars(initp, csite,ipa)
   use rk4_coms              , only : rk4site               & ! intent(in)
                                    , rk4tiny_sfcw_mass     & ! intent(in)
                                    , rk4min_sfcw_mass      & ! intent(in)
                                    , rk4min_can_shv        & ! intent(in)
                                    , rk4min_can_theta      & ! intent(in)
                                    , rk4max_can_theta      & ! intent(in)
                                    , rk4min_can_lntheta    & ! intent(in)
                                    , rk4max_can_lntheta    & ! intent(in)
                                    , rk4min_can_temp       & ! intent(in)
                                    , rk4max_can_shv        & ! intent(in)
                                    , rk4patchtype          ! ! structure
   use ed_state_vars         , only : sitetype              & ! structure
                                    , patchtype             ! ! structure
   use soil_coms             , only : soil8                 ! ! intent(in)
   use grid_coms             , only : nzg                   & ! intent(in)
                                    , nzs                   ! ! intent(in)
   use therm_lib8            , only : qwtk8                 & ! subroutine
                                    , qtk8                  & ! subroutine
                                    , thetaeiv8             & ! function
                                    , rehuil8               & ! function
                                    , rslif8                & ! function
                                    , thrhsh2temp8          ! ! function
   use consts_coms           , only : alvl8                 & ! intent(in)
                                    , wdns8                 & ! intent(in)
                                    , rdryi8                & ! intent(in)
                                    , rdry8                 & ! intent(in)
                                    , epim18                & ! intent(in)
                                    , toodry8               & ! intent(in)
                                    , cp8                   & ! intent(in)
                                    , cpi8                  & ! intent(in)
                                    , p00i8                 & ! intent(in)
                                    , rocp8                 & ! intent(in)
                                    , t3ple8                ! ! intent(in)
   use canopy_struct_dynamics, only : can_whcap8            ! ! subroutine
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype) , target     :: initp
   type(sitetype)     , target     :: csite
   integer            , intent(in) :: ipa
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)        , pointer :: cpatch
   integer                          :: ico
   integer                          :: k
   integer                          :: ksn
   integer                          :: kclosest
   logical                          :: ok_shv
   logical                          :: ok_theta
   real(kind=8)                     :: soilhcap
   real(kind=8)                     :: int_sfcwater_energy
   real(kind=8)                     :: sum_sfcw_mass
   real(kind=8)                     :: sum_sfcw_depth
   !---------------------------------------------------------------------------------------!

   !----- First, we update the canopy air equivalent potential temperature. ---------------!
   initp%can_theta = exp(initp%can_lntheta)

   !----- Then we define some logicals to make the code cleaner. --------------------------!
   ok_shv   = initp%can_shv     >= rk4min_can_shv     .and.                                &
              initp%can_shv     <= rk4max_can_shv
   ok_theta = initp%can_lntheta >= rk4min_can_lntheta .and.                                &
              initp%can_lntheta <= rk4max_can_lntheta

   !---------------------------------------------------------------------------------------!
   !     Here we convert theta into temperature, potential temperature, and density, and   !
   ! ice-vapour equivalent potential temperature.  The latter variable (or its natural     !
   ! log) should eventually become the prognostic variable for canopy air space entropy    !
   ! when we add condensed/frozen water in the canopy air space.                           !
   !---------------------------------------------------------------------------------------!
   if (ok_shv .and. ok_theta) then
      initp%can_rvap  = initp%can_shv / (1.d0 - initp%can_shv)
      initp%can_temp  = thrhsh2temp8(initp%can_theta,initp%can_rhos,initp%can_shv)
      initp%can_prss  = initp%can_rhos * rdry8 * initp%can_temp                            &
                      * (1.d0 + epim18 * initp%can_shv)
      initp%can_exner = cp8 * (initp%can_prss * p00i8) ** rocp8
      initp%can_rhv   = rehuil8(initp%can_prss,initp%can_temp,initp%can_rvap)
      initp%can_ssh   = rslif8(initp%can_prss,initp%can_temp)
      initp%can_theiv = thetaeiv8(initp%can_theta,initp%can_prss,initp%can_temp            &
                                 ,initp%can_rvap,initp%can_rvap)
   elseif (initp%can_lntheta >= rk4max_can_lntheta) then
      initp%can_theta = rk4max_can_theta + 1.d0
   elseif (initp%can_lntheta <= rk4min_can_lntheta) then
      initp%can_theta = rk4min_can_theta - 1.d0
   end if
   !---------------------------------------------------------------------------------------!


   !----- Updating soil temperature and liquid water fraction. ----------------------------!
   do k = rk4site%lsl, nzg - 1
      soilhcap = soil8(csite%ntext_soil(k,ipa))%slcpd
      call qwtk8(initp%soil_energy(k),initp%soil_water(k)*wdns8,soilhcap                   &
                ,initp%soil_tempk(k),initp%soil_fracliq(k))
   end do
   !---------------------------------------------------------------------------------------!

   call can_whcap8(csite,ipa,initp%can_rhos,initp%can_temp,initp%can_depth)

   !---------------------------------------------------------------------------------------!
   !    Updating surface water temperature and liquid water fraction, remembering that in- !
   ! side the RK4 integration, surface water energy is in J/m�. The abs is necessary be-   !
   ! cause surface mass may indeed become too negative during the integration process and  !
   ! if it happens, we want the step to be rejected.                                       !
   !---------------------------------------------------------------------------------------!
   sum_sfcw_depth = 0.d0
   sum_sfcw_mass  = 0.d0
   ksn = initp%nlev_sfcwater
   do k = 1,ksn
      sum_sfcw_depth = sum_sfcw_depth + initp%sfcwater_depth(k)
      sum_sfcw_mass  = sum_sfcw_mass  + initp%sfcwater_mass (k)
   end do

   if (sum_sfcw_mass >= rk4min_sfcw_mass) then
      sfcwloop: do k=1,ksn
         if (initp%sfcwater_mass(k) > rk4tiny_sfcw_mass) then
            !------------------------------------------------------------------------------!
            !      Convert surface water energy from extensive quantity (J/m2) to          !
            ! intensive quantity (J/kg), then update the temperature and liquid water      !
            ! fraction.                                                                    !
            !------------------------------------------------------------------------------!
            int_sfcwater_energy = initp%sfcwater_energy(k)/initp%sfcwater_mass(k)
            call qtk8(int_sfcwater_energy,initp%sfcwater_tempk(k),initp%sfcwater_fracliq(k))
         else
            write (unit=*,fmt='(a)') '----------------------------------------------------'
            write (unit=*,fmt='(a)') ' - Temporary surface water makes no sense!'
            write (unit=*,fmt='(a,1x,es12.5)') ' - LONGITUDE      : ',rk4site%lon
            write (unit=*,fmt='(a,1x,es12.5)') ' - LATITUDE       : ',rk4site%lat
            write (unit=*,fmt='(a,1x,i12)') ' - PATCH          : ',ipa
            write (unit=*,fmt='(a,1x,i12)') ' - NLEV_SFCW      : ',initp%nlev_sfcwater
            write (unit=*,fmt='(a,1x,i12)') ' - THIS LEVEL     : ',k
            write (unit=*,fmt='(a,1x,i12)') ' - MASS           : ',initp%sfcwater_mass  (k)
            write (unit=*,fmt='(a,1x,i12)') ' - ENERGY         : ',initp%sfcwater_energy(k)
            write (unit=*,fmt='(a,1x,i12)') ' - DEPTH          : ',initp%sfcwater_depth (k)
            write (unit=*,fmt='(a,1x,i12)') ' - MIN_SFCW_MASS  : ',rk4min_sfcw_mass
            write (unit=*,fmt='(a,1x,i12)') ' - TINY_SFCW_MASS : ',rk4tiny_sfcw_mass
            write (unit=*,fmt='(a)') '----------------------------------------------------'
            call fatal_error('Inconsistent surface water properties'                       &
                            ,'update_diagnostic_vars','rk4_misc.f90')
         end if
      end do sfcwloop
      nosfcwloop: do k=ksn+1,nzs
         if (k == 1) then
            initp%sfcwater_energy(k)  = 0.d0
            initp%sfcwater_mass(k)    = 0.d0
            initp%sfcwater_depth(k)   = 0.d0
            initp%sfcwater_tempk(k)   = initp%soil_tempk(nzg)
            initp%sfcwater_fracliq(k) = initp%soil_fracliq(nzg)
         else
            initp%sfcwater_energy(k)  = 0.d0
            initp%sfcwater_mass(k)    = 0.d0
            initp%sfcwater_depth(k)   = 0.d0
            initp%sfcwater_tempk(k)   = initp%sfcwater_tempk(k-1)
            initp%sfcwater_fracliq(k) = initp%sfcwater_fracliq(k-1)
         end if
      end do nosfcwloop
   end if

   cpatch => csite%patch(ipa)

   !----- Loop over cohorts ---------------------------------------------------------------!
   cohortloop: do ico=1,cpatch%ncohorts
      !----- Checking whether this is a prognostic cohort... ------------------------------!
      if (initp%solvable(ico)) then
         !---------------------------------------------------------------------------------!
         !     We compute the minimum leaf water, and decide whether we can compute the    !
         ! temperature and liquid water fraction.                                          !
         !---------------------------------------------------------------------------------!
         
         !----- Lastly we update leaf temperature and liquid fraction. --------------------!
         call qwtk8(initp%veg_energy(ico),initp%veg_water(ico),initp%hcapveg(ico)          &
                   ,initp%veg_temp(ico),initp%veg_fliq(ico))
      elseif (dble(cpatch%hite(ico)) <= sum_sfcw_depth) then
         !---------------------------------------------------------------------------------!
         !    For plants buried in snow or under water, fix the leaf temperature to the    !
         ! snow/ponding temperature of the layer that is the closest to the leaves.        !
         !---------------------------------------------------------------------------------!
         kclosest = 1
         do k = initp%nlev_sfcwater, 1, -1
            if (sum(initp%sfcwater_depth(1:k)) > dble(cpatch%hite(ico))) kclosest = k
         end do
         initp%veg_temp(ico)   = initp%sfcwater_tempk(kclosest)
         initp%veg_water(ico)  = 0.d0
         initp%veg_energy(ico) = initp%hcapveg(ico) * initp%veg_temp(ico)
         if (initp%veg_temp(ico) == t3ple8) then
            initp%veg_fliq(ico) = 5.d-1
         elseif (initp%veg_temp(ico) > t3ple8) then
            initp%veg_fliq(ico) = 1.d0
         else
            initp%veg_fliq(ico) = 0.d0
         end if
      else
         !---------------------------------------------------------------------------------!
         !     For plants with minimal foliage or very sparse patches, fix the leaf        !
         ! temperature to the canopy air space and force veg_water to be zero.             !
         !---------------------------------------------------------------------------------!
         initp%veg_temp(ico)   = initp%can_temp
         initp%veg_water(ico)  = 0.d0
         initp%veg_energy(ico) = initp%hcapveg(ico) * initp%veg_temp(ico)
         if (initp%veg_temp(ico) == t3ple8) then
            initp%veg_fliq(ico) = 5.d-1
         elseif (initp%veg_temp(ico) > t3ple8) then
            initp%veg_fliq(ico) = 1.d0
         else
            initp%veg_fliq(ico) = 0.d0
         end if
      end if
   end do cohortloop

   return
end subroutine update_diagnostic_vars
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutine performs the following tasks:                                         !
! 1. Check how many layers of temporary water or snow we have, and include the virtual     !
!    pools at the topmost if needed;                                                       !
! 2. Force thermal equilibrium between topmost soil layer and a single snow/water layer    !
!    if the layer is too thin;                                                             !
! 3. Compute the amount of mass each layer has, and redistribute them accordingly.         !
! 4. Percolates excessive liquid water if needed.                                          !
!------------------------------------------------------------------------------------------!
subroutine adjust_sfcw_properties(nzg,nzs,initp,csite,ipa)

   use rk4_coms      , only : rk4patchtype          & ! structure
                            , rk4min_sfcw_mass      & ! intent(in)
                            , rk4min_virt_water     & ! intent(in)
                            , rk4water_stab_thresh  & ! intent(in)
                            , rk4tiny_sfcw_mass     & ! intent(in)
                            , rk4tiny_sfcw_depth     & ! intent(in)
                            , rk4snowmin            & ! intent(in)
                            , newsnow               & ! intent(in)
                            , rk4eps2               ! ! intent(in)
   use ed_state_vars , only : sitetype              & ! structure
                            , patchtype             ! ! structure
   use soil_coms     , only : soil8                 & ! intent(in)
                            , dslz8                 & ! intent(in)
                            , dslzi8                & ! intent(in)
                            , thick                 & ! intent(in)
                            , thicknet              ! ! intent(in)
   use consts_coms   , only : cice8                 & ! intent(in)
                            , cliq8                 & ! intent(in)
                            , t3ple8                & ! intent(in)
                            , wdns8                 & ! intent(in)
                            , wdnsi8                & ! intent(in)
                            , tsupercool8           & ! intent(in)
                            , qliqt38               & ! intent(in)
                            , wdnsi8                ! ! intent(in)
   use therm_lib8    , only : qtk8                  & ! subroutine
                            , qwtk8                 ! ! subroutine
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype)     , target     :: initp
   type(sitetype)         , target     :: csite
   integer                , intent(in) :: ipa
   integer                , intent(in) :: nzg
   integer                , intent(in) :: nzs
   !----- Local variables -----------------------------------------------------------------!
   integer                             :: kold
   integer                             :: newlayers
   integer                             :: nlayers
   integer                             :: ksn
   integer                             :: ksnnew
   integer                             :: k
   !----- Control variables ---------------------------------------------------------------!
   real(kind=8)                        :: wtold
   real(kind=8)                        :: wtnew
   real(kind=8), dimension(nzs)        :: newsfcw_mass
   real(kind=8), dimension(nzs)        :: newsfcw_energy
   real(kind=8), dimension(nzs)        :: newsfcw_depth
   real(kind=8)                        :: wdiff
   real(kind=8)                        :: sum_sfcw_mass
   real(kind=8)                        :: sum_sfcw_energy
   real(kind=8)                        :: sum_sfcw_depth
   real(kind=8)                        :: energy_free
   real(kind=8)                        :: wmass_free
   real(kind=8)                        :: depth_free
   real(kind=8)                        :: wmass_perc
   real(kind=8)                        :: energy_perc
   real(kind=8)                        :: depth_perc
   real(kind=8)                        :: i_energy_try
   real(kind=8)                        :: energy_try
   real(kind=8)                        :: wmass_try
   real(kind=8)                        :: depth_try
   real(kind=8)                        :: temp_try
   real(kind=8)                        :: fliq_try
   real(kind=8)                        :: energy_tot
   real(kind=8)                        :: wmass_tot
   real(kind=8)                        :: hcapdry_tot
   real(kind=8)                        :: wmass_room
   real(kind=8)                        :: depthloss
   real(kind=8)                        :: snden
   real(kind=8)                        :: sndenmin
   real(kind=8)                        :: sndenmax
   real(kind=8)                        :: Cr               ! snow waterholding capacity
   real(kind=8)                        :: gi               ! Partial density of ice
   integer                             :: nsoil
   !----- Variables used for the water and energy budget. ---------------------------------!
   real(kind=8)                        :: wmass_virtual_beg
   real(kind=8)                        :: energy_virtual_beg
   real(kind=8)                        :: wmass_sfcw_beg
   real(kind=8)                        :: energy_sfcw_beg
   real(kind=8)                        :: wmass_soil_beg
   real(kind=8)                        :: energy_soil_beg
   real(kind=8)                        :: wmass_total_beg
   real(kind=8)                        :: energy_total_beg
   real(kind=8)                        :: wmass_virtual_end
   real(kind=8)                        :: energy_virtual_end
   real(kind=8)                        :: wmass_sfcw_end
   real(kind=8)                        :: energy_sfcw_end
   real(kind=8)                        :: wmass_soil_end
   real(kind=8)                        :: energy_soil_end
   real(kind=8)                        :: wmass_total_end
   real(kind=8)                        :: energy_total_end
   real(kind=8)                        :: wmass_total_rch
   real(kind=8)                        :: energy_total_rch
   !----- Constants -----------------------------------------------------------------------!
   logical                , parameter  :: debug   = .false.
   real(kind=8)           , parameter  :: Crmin   = 3.d-2
   real(kind=8)           , parameter  :: Crmax   = 1.d-1
   real(kind=8)           , parameter  :: ge      = 2.d2
   !---------------------------------------------------------------------------------------!


   !----- Copy the original number of temporary surface water layers to ksn. --------------!
   ksn       = initp%nlev_sfcwater
   !---------------------------------------------------------------------------------------!



   !----- Copy the soil type at the topmost level to nsoil. -------------------------------!
   nsoil     = csite%ntext_soil(nzg,ipa)
   !---------------------------------------------------------------------------------------!
   


   !---------------------------------------------------------------------------------------!
   !      Determine the total amount of temporary surface water available as well as       !
   ! derived properties.                                                                   !
   !---------------------------------------------------------------------------------------!
   sum_sfcw_mass   = 0.d0
   sum_sfcw_energy = 0.d0
   sum_sfcw_depth  = 0.d0
   do k=1,ksn
      sum_sfcw_mass   = sum_sfcw_mass   + initp%sfcwater_mass  (k)
      sum_sfcw_energy = sum_sfcw_energy + initp%sfcwater_energy(k)
      sum_sfcw_depth  = sum_sfcw_depth  + initp%sfcwater_depth (k)
   end do
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !      Initialise the budget variables.                                                 !
   !---------------------------------------------------------------------------------------!
   wmass_virtual_beg  = initp%virtual_water
   energy_virtual_beg = initp%virtual_heat
   wmass_sfcw_beg     = sum_sfcw_mass
   energy_sfcw_beg    = sum_sfcw_energy
   wmass_soil_beg     = initp%soil_water(nzg)  * dslz8(nzg) * wdns8
   energy_soil_beg    = initp%soil_energy(nzg) * dslz8(nzg)
   wmass_total_beg    = wmass_virtual_beg  + wmass_sfcw_beg  + wmass_soil_beg
   energy_total_beg   = energy_virtual_beg + energy_sfcw_beg + energy_soil_beg
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Check the total amount of water that has just fallen plus the amount that is al-  !
   ! ready sitting over the top soil layer.  We must do this as the first step because we  !
   ! may want to eliminate this water by binding it to the top soil layer in case there is !
   ! too little water.                                                                     !
   !---------------------------------------------------------------------------------------!
   if (initp%virtual_water < rk4min_virt_water .or. sum_sfcw_mass < rk4min_sfcw_mass ) then
      !------------------------------------------------------------------------------------!
      !     Either the virtual layer or the temporary surface water has too negative mass, !
      ! so this step doesn't make sense.  We quit the sub-routine here so the sanity check !
      ! can reject this step.                                                              !
      !------------------------------------------------------------------------------------!
      return
   elseif ((initp%virtual_water + sum_sfcw_mass) < rk4min_sfcw_mass  .or.                  &
           (initp%virtual_water + sum_sfcw_mass) < rk4min_virt_water      ) then
      !------------------------------------------------------------------------------------!
      !    Neither the virtual layer nor the temporary surface water are too negative,     !
      ! but the sum of both is.  We eliminitate the temporary surface water, add them to   !
      ! the virtual pool, so this way the step will be rejected.                           !
      !------------------------------------------------------------------------------------!
      initp%virtual_water      = initp%virtual_water  + sum_sfcw_mass
      initp%virtual_heat       = initp%virtual_heat   + sum_sfcw_energy
      initp%virtual_depth      = initp%virtual_depth  + sum_sfcw_depth
      !----- Reset both the temporary surface water. --------------------------------------!
      initp%nlev_sfcwater      = 0
      initp%sfcwater_mass  (:) = 0.d0
      initp%sfcwater_energy(:) = 0.d0
      initp%sfcwater_depth (:) = 0.d0
      return
   elseif ((initp%virtual_water + sum_sfcw_mass) < rk4tiny_sfcw_mass) then
      !------------------------------------------------------------------------------------!
      !     The mass of the potential new temporary surface water is within bounds but it  !
      ! is too small to be maintained.  We add both the virtual mass and the total surface !
      ! water and dump in the free water, but set ksnnew to zero so all the water is       !
      ! infiltrated in the top soil layer.                                                 !
      !------------------------------------------------------------------------------------!
      wmass_free               = initp%virtual_water + sum_sfcw_mass
      energy_free              = initp%virtual_heat  + sum_sfcw_energy
      depth_free               = initp%virtual_depth + sum_sfcw_depth
      !----- Reset both the temporary surface water and the virtual layer. ----------------!
      initp%virtual_water      = 0.d0
      initp%virtual_heat       = 0.d0
      initp%virtual_depth      = 0.d0
      initp%sfcwater_mass  (:) = 0.d0
      initp%sfcwater_energy(:) = 0.d0
      initp%sfcwater_depth (:) = 0.d0
      !----- Set ksnnew to zero to force all free water to go to the soil. ----------------!
      ksnnew                   = 0
   else
      !------------------------------------------------------------------------------------!
      !     The mass of the potential new temporary surface water is within bounds and     !
      ! could create at least one layer.  If there is already a temporary surface water or !
      ! snow layer, the new amount is initially put there, otherwise, we attempt to create !
      ! the first layer.                                                                   !
      !------------------------------------------------------------------------------------!
      wmass_free               = initp%virtual_water
      energy_free              = initp%virtual_heat
      depth_free               = initp%virtual_depth
      initp%virtual_water      = 0.d0
      initp%virtual_heat       = 0.d0
      initp%virtual_depth      = 0.d0
      ksnnew                   = max(ksn,1)
   end if
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !    Update the prognostic and diagnostic variables by adding the free standing water.  !
   ! Then we check the size of the temporary surface water layers, and update the          !
   ! temperature in a way that ensure the layer stability.  During this process, we        !
   ! update the total temporary surface water mass, energy, and depth, which will be used  !
   ! later in the sub-routine.                                                             !
   !---------------------------------------------------------------------------------------!
   sum_sfcw_mass   = 0.d0
   sum_sfcw_energy = 0.d0
   sum_sfcw_depth  = 0.d0
   do k = ksnnew,1,-1
      !------------------------------------------------------------------------------------!
      !    Find the potential mass, energy, and depth of the temporary layer if all the    !
      ! free water became part of this layer.                                              !
      !------------------------------------------------------------------------------------!
      energy_try = initp%sfcwater_energy(k) + energy_free
      wmass_try  = initp%sfcwater_mass(k)   + wmass_free
      depth_try  = initp%sfcwater_depth(k)  + depth_free
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !    In case this is a single layer, and a very thin one, we may have a hard time    !
      ! achieving numerical stability.  We can treat this case like the leaf case, in      !
      ! the sense that the water sitting on the top of the surface is in thermal           !
      ! equilibrium with the surface.                                                      !
      !------------------------------------------------------------------------------------!
      if (ksnnew == 1 .and. wmass_try < rk4water_stab_thresh) then
         !---------------------------------------------------------------------------------!
         !     Find the total internal energy of the combined pool (top soil layer plus    !
         ! the thin temporary surface water).  The units of soil properties are J/m3 for   !
         ! the internal energy, and m3/m3 for soil water, whilst the temporary surface     !
         ! water has units of J/m2 for internal energy and kg/m2 for mass.  We use the     !
         ! standard for the temporary surface water.                                       !
         !---------------------------------------------------------------------------------!
         energy_tot  = energy_try + initp%soil_energy(nzg) * dslz8(nzg)
         wmass_tot   = wmass_try  + initp%soil_water(nzg)  * dslz8(nzg) * wdns8
         hcapdry_tot = soil8(nsoil)%slcpd * dslz8(nzg)
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !      Find the equilibrium temperature and liquid/ice partition.   Because we    !
         ! are assuming thermal equilibrium, the temperature and liquid fraction of the    !
         ! attempted layer is the same as the average temperature of the augmented pool.   !
         !---------------------------------------------------------------------------------!
         call qwtk8(energy_tot,wmass_tot,hcapdry_tot,temp_try,fliq_try)
         !---------------------------------------------------------------------------------!


         !---------------------------------------------------------------------------------!
         !    Re-compute the internal energy of the temporary layer, using the temperature !
         ! and fraction of liquid water distribution we have just found, keeping the mass  !
         ! constant.                                                                       !
         !---------------------------------------------------------------------------------!
         energy_try = wmass_try * (         fliq_try  * cliq8 * (temp_try - tsupercool8)   &
                                  + (1.d0 - fliq_try) * cice8 *  temp_try                )
         !---------------------------------------------------------------------------------!



         !---------------------------------------------------------------------------------!
         !    Re-calculate the top soil internal energy, by removing the attempted surface !
         ! water energy from the total energy, and converting it back to J/m3.  The total  !
         ! amount of water does not need to be re-calculated at this time.                 !
         !---------------------------------------------------------------------------------!
         initp%soil_energy(nzg)  = (energy_tot - energy_try) * dslzi8(nzg)
         !---------------------------------------------------------------------------------!
      else
         !---------------------------------------------------------------------------------!
         !      Layer is computationally stable, find temperature and liquid fraction of   !
         ! the attempted layer.                                                            !
         !---------------------------------------------------------------------------------!
         i_energy_try = energy_try / wmass_try
         call qtk8(i_energy_try,temp_try,fliq_try)
        !---------------------------------------------------------------------------------!
      end if
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !     Determine a first guess for the amount of mass that can be lost from this      !
      ! layer through percolation (wmass_perc).                                            !
      !------------------------------------------------------------------------------------!
      if (newsnow) then
         !---------------------------------------------------------------------------------!
         !    Alternative "free" water calculation.                                        !
         !    Anderson (1976), NOAA Tech Report NWS 19.                                    !
         !---------------------------------------------------------------------------------!
         gi          = wmass_try/max(rk4tiny_sfcw_depth,depth_try) * (1.d0 - fliq_try)
         Cr          = max(Crmin, Crmin + (Crmax - Crmin) * (ge - gi) / ge)
         wmass_perc  = max(0.d0,wmass_try * (fliq_try - Cr / (1.d0 + Cr)))
         !---------------------------------------------------------------------------------!
      else
         !---------------------------------------------------------------------------------!
         !     Original method, from LEAF-3.  Shed liquid in excess of a 1:9               !
         ! liquid-to-ice ratio through percolation.                                        !
         !---------------------------------------------------------------------------------!
         wmass_perc  = max(0.d0, wmass_try * (fliq_try - 1.d-1) / 9.d-1)
         !---------------------------------------------------------------------------------!
      end if
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !     Determinte whether the layer beneath the current one is another temporary      !
      ! surface water/snow layer, or the top soil layer.  In case it is the latter, we     !
      ! must check whether there is enough room for the percolate water to infiltrate      !
      ! (i.e., the soil will not become super-saturated), in which case we must reduce the !
      ! total amount of percolation.                                                       !
      !------------------------------------------------------------------------------------!
      if (k == 1) then
         !---------------------------------------------------------------------------------!
         !     Compute the available "room" for water at the top soil layer.  We must      !
         ! multiply by density and depth to make sure that the units match.                !
         !---------------------------------------------------------------------------------!
         wmass_room = max(0.d0, soil8(nsoil)%slmsts - initp%soil_water(nzg))               &
                    * wdns8 * dslz8(nzg) 
         wmass_perc = min(wmass_perc,wmass_room)
         !---------------------------------------------------------------------------------!
      end if
      !------------------------------------------------------------------------------------!





      !------------------------------------------------------------------------------------!
      !     Re-calculate the total water mass and energy of this temporary surface water.  !
      ! Here we must check whether the soil layer would be with too little mass, and if    !
      ! that is the case, we will eliminate the layer by forcing the tiny left-over to go  !
      ! to the layer beneath.                                                              !
      !------------------------------------------------------------------------------------!
      if (wmass_try - wmass_perc > rk4tiny_sfcw_mass) then
         !---------------------------------------------------------------------------------!
         !      Enough mass to keep this layer.                                            !
         !---------------------------------------------------------------------------------!
         !----- Compute the internal energy and depth associated with percolated water. ---!
         energy_perc = wmass_perc * cliq8 * (temp_try - tsupercool8)
         depth_perc  = wmass_perc * wdnsi8
         !----- Find the new water mass and energy for this layer. ------------------------!
         initp%sfcwater_mass  (k) = wmass_try  - wmass_perc
         initp%sfcwater_energy(k) = energy_try - energy_perc

         !---------------------------------------------------------------------------------!
         !      Calculate density and depth of snow.  Start with the difference of depths, !
         ! but then we adjust it because the loss through percolation changes the ratio    !
         ! between ice and liquid in this layer                                            !
         !---------------------------------------------------------------------------------!
         initp%sfcwater_depth (k) = depth_try  - depth_perc
         snden    = initp%sfcwater_mass(k)                                                 &
                  / max(rk4tiny_sfcw_depth,initp%sfcwater_depth(k))
         sndenmax = wdns8
         sndenmin = max(3.d1, 2.d2 * (wmass_free + wmass_perc) / initp%sfcwater_mass(k) )
         snden    = min(sndenmax, max(sndenmin,snden))
         initp%sfcwater_depth (k) = initp%sfcwater_mass(k) / snden
      else
         !---------------------------------------------------------------------------------!
         !      The layer would be too small, eliminate mass from this layer and send all  !
         ! mass to the layer beneath as percolated water.                                  !
         !---------------------------------------------------------------------------------!
         initp%sfcwater_mass  (k) = 0.d0
         initp%sfcwater_energy(k) = 0.d0
         initp%sfcwater_depth (k) = 0.d0
         wmass_perc               = wmass_try
         energy_perc              = energy_try
         depth_perc               = depth_try
      end if
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !     Integrate the total temporary surface water properties.                        !
      !------------------------------------------------------------------------------------!
      sum_sfcw_mass   = sum_sfcw_mass   + initp%sfcwater_mass  (k)
      sum_sfcw_energy = sum_sfcw_energy + initp%sfcwater_energy(k)
      sum_sfcw_depth  = sum_sfcw_depth  + initp%sfcwater_depth (k)
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !     The water available for the layer beneath is going to be the total percolated  !
      ! water.                                                                             !
      !------------------------------------------------------------------------------------!
      wmass_free  = wmass_perc
      energy_free = energy_perc
      depth_free  = depth_perc
      !------------------------------------------------------------------------------------!
   end do
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Add any remaining free water to the top soil layer.                               !
   !---------------------------------------------------------------------------------------!
   initp%soil_water(nzg)  = initp%soil_water(nzg)  + wmass_free  * dslzi8(nzg) * wdnsi8
   initp%soil_energy(nzg) = initp%soil_energy(nzg) + energy_free * dslzi8(nzg)
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !     Check the total amount of mass in the temporary surface water/snow, and adjust    !
   ! the number of layer accordingly.                                                      !
   !---------------------------------------------------------------------------------------!
   if (sum_sfcw_mass <= rk4tiny_sfcw_mass) then
      !----- Not enough water in the temporary surface water, eliminate all layers. -------!
      initp%nlev_sfcwater = 0
      !------------------------------------------------------------------------------------!



      !------------------------------------------------------------------------------------!
      !      The total mass should be either zero or greater than rk4tiny_sfcw_mass,       !
      ! but, just in case, we add any remaining energy to the top soil layer.              !
      !------------------------------------------------------------------------------------!
      initp%soil_water(nzg)  = initp%soil_water(nzg)  + sum_sfcw_mass   * dslzi8(nzg)      &
                                                      * wdnsi8
      initp%soil_energy(nzg) = initp%soil_energy(nzg) + sum_sfcw_energy * dslzi8(nzg)
      !------------------------------------------------------------------------------------!

      !----- Loop all layers and re-set all extensive variables to zero. ------------------!
      do k = 1, nzs
         initp%sfcwater_mass(k)    = 0.d0
         initp%sfcwater_energy(k)  = 0.d0
         initp%sfcwater_depth(k)   = 0.d0
      end do
      !------------------------------------------------------------------------------------!
   else
      !---- Check whether there is enough snow for a new layer. ---------------------------!
      nlayers   = ksnnew
      newlayers = 1
      do k = 1,nzs
         !---------------------------------------------------------------------------------!
         !     Check whether the layer as is meet the minimum requirements to stand as a   !
         ! new layer by itself.                                                            !
         !---------------------------------------------------------------------------------!
         if ( initp%sfcwater_mass(k)   >  rk4tiny_sfcw_mass              .and.             &
              rk4snowmin * thicknet(k) <= sum_sfcw_mass                  .and.             &
              initp%sfcwater_energy(k) <  initp%sfcwater_mass(k)*qliqt38       ) then
            newlayers = newlayers + 1
         end if
         !---------------------------------------------------------------------------------!
      end do

      !----- Newlayers is the new number of temporary surface water layers. ---------------!
      newlayers = min(newlayers, nzs, nlayers + 1)
      
      if (newlayers == 1) then
         newsfcw_mass  (1) = sum_sfcw_mass
         newsfcw_energy(1) = sum_sfcw_energy
         newsfcw_depth (1) = sum_sfcw_depth
      else
         kold  = 1
         wtnew = 1.d0
         wtold = 1.d0
         do k = 1,newlayers
            newsfcw_mass(k)   = sum_sfcw_mass * thick(k,newlayers)
            newsfcw_energy(k) = 0.d0
            newsfcw_depth(k)  = 0.d0
            !----- Find the properties of this new layer. ---------------------------------!
            find_layer: do

               !----- Difference between old and new snow ---------------------------------!
               wdiff = wtnew * newsfcw_mass(k) - wtold * initp%sfcwater_mass(kold)  

               if (wdiff > 0.d0) then
                  newsfcw_energy(k) = newsfcw_energy(k)                                    &
                                    + wtold * initp%sfcwater_energy(kold)
                  newsfcw_depth(k)  = newsfcw_depth(k)                                     &
                                    + wtold * initp%sfcwater_depth(kold)
                  wtnew  = wtnew - wtold * initp%sfcwater_mass(kold) / newsfcw_mass(k)
                  kold   = kold + 1
                  wtold  = 1.0
                  if (kold > nlayers) exit find_layer
               else
                  newsfcw_energy(k) = newsfcw_energy(k) + wtnew * newsfcw_mass(k)             &
                                    * initp%sfcwater_energy(kold)                             &
                                    / max(rk4tiny_sfcw_mass,initp%sfcwater_mass(kold))
                  newsfcw_depth(k)  = newsfcw_depth(k)  + wtnew * newsfcw_mass(k)             &
                                    * initp%sfcwater_depth(kold)                              &
                                    / max(rk4tiny_sfcw_mass,initp%sfcwater_mass(kold))
                  wtold = wtold - wtnew * newsfcw_mass(k)                                     &
                                / max(rk4tiny_sfcw_mass,initp%sfcwater_mass(kold))
                  wtnew = 1.
                  exit find_layer
               end if
            end do find_layer
         end do
      end if

      !----- Update the water/snow layer prognostic properties. ---------------------------!
      initp%nlev_sfcwater = newlayers
      do k = 1,newlayers
         initp%sfcwater_mass(k)   = newsfcw_mass(k)
         initp%sfcwater_energy(k) = newsfcw_energy(k)
         initp%sfcwater_depth(k)  = newsfcw_depth(k)
      end do
      do k = newlayers + 1, nzs
         initp%sfcwater_mass   (k) = 0.d0
         initp%sfcwater_energy (k) = 0.d0
         initp%sfcwater_depth  (k) = 0.d0
      end do
   end if
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !      Compute the budget variables after the adjustments.                              !
   !---------------------------------------------------------------------------------------!
   wmass_virtual_end  = initp%virtual_water
   energy_virtual_end = initp%virtual_heat
   wmass_sfcw_end     = sum_sfcw_mass
   energy_sfcw_end    = sum_sfcw_energy
   wmass_soil_end     = initp%soil_water(nzg)  * dslz8(nzg) * wdns8
   energy_soil_end    = initp%soil_energy(nzg) * dslz8(nzg)
   wmass_total_end    = wmass_virtual_end  + wmass_sfcw_end  + wmass_soil_end
   energy_total_end   = energy_virtual_end + energy_sfcw_end + energy_soil_end
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !      Check whether energy and mass are conserved.                                     !
   !---------------------------------------------------------------------------------------!
   wmass_total_rch  = 2.d0 * abs(wmass_total_end - wmass_total_beg)                        &
                    / (abs(wmass_total_end) + abs(wmass_total_beg))
   energy_total_rch = 2.d0 * abs(energy_total_end - energy_total_beg)                      &
                    / (abs(energy_total_end) + abs(energy_total_beg))
   if (wmass_total_rch > 1.d-6 .or. energy_total_rch > 1.d-6) then
      write (unit=*,fmt='(a)')           '------------------------------------------------'
      write (unit=*,fmt='(a)')           ' Water or energy conservation was violated!!!   '
      write (unit=*,fmt='(a)')           '------------------------------------------------'
      write (unit=*,fmt='(a)')           ' '
      write (unit=*,fmt='(a)')           ' - Initial conditions: '
      write (unit=*,fmt='(a,1x,es14.7)') '   + Total water mass    = ',wmass_total_beg
      write (unit=*,fmt='(a,1x,es14.7)') '   + Virtual mass        = ',wmass_virtual_beg
      write (unit=*,fmt='(a,1x,es14.7)') '   + Ponding/snow mass   = ',wmass_sfcw_beg
      write (unit=*,fmt='(a,1x,es14.7)') '   + Soil mass           = ',wmass_soil_beg
      write (unit=*,fmt='(a,1x,es14.7)') '   + Total energy        = ',energy_total_beg
      write (unit=*,fmt='(a,1x,es14.7)') '   + Virtual energy      = ',energy_virtual_beg
      write (unit=*,fmt='(a,1x,es14.7)') '   + Ponding/snow energy = ',energy_sfcw_beg
      write (unit=*,fmt='(a,1x,es14.7)') '   + Soil energy         = ',energy_soil_beg
      write (unit=*,fmt='(a)')           ' '
      write (unit=*,fmt='(a)')           ' - Final conditions: '
      write (unit=*,fmt='(a,1x,es14.7)') '   + Total water mass    = ',wmass_total_end
      write (unit=*,fmt='(a,1x,es14.7)') '   + Virtual mass        = ',wmass_virtual_end
      write (unit=*,fmt='(a,1x,es14.7)') '   + Ponding/snow mass   = ',wmass_sfcw_end
      write (unit=*,fmt='(a,1x,es14.7)') '   + Soil mass           = ',wmass_soil_end
      write (unit=*,fmt='(a,1x,es14.7)') '   + Total energy        = ',energy_total_end
      write (unit=*,fmt='(a,1x,es14.7)') '   + Virtual energy      = ',energy_virtual_end
      write (unit=*,fmt='(a,1x,es14.7)') '   + Ponding/snow energy = ',energy_sfcw_end
      write (unit=*,fmt='(a,1x,es14.7)') '   + Soil energy         = ',energy_soil_end
      write (unit=*,fmt='(a)')           ' '
      write (unit=*,fmt='(a)')           ' - Relative error: '
      write (unit=*,fmt='(a,1x,es14.7)') '   + Total water mass    = ',wmass_total_rch
      write (unit=*,fmt='(a,1x,es14.7)') '   + Total energy        = ',energy_total_rch
      write (unit=*,fmt='(a)')           ' '
      write (unit=*,fmt='(a)')           '------------------------------------------------'
      call fatal_error('Energy or water is not being conserved!!!'                         &
                      ,'adjust_sfcw_properties','rk4_misc.f90')
   end if

   return
end subroutine adjust_sfcw_properties
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutine will ensure that leaf water is positively defined.  Depending on its  !
! derivative, it can go under zero, in which case we must correct the derivatives rather   !
! than forcing it to be zero.  This guarantees mass conservation.  Likewise, if in the end !
! of the step the leaf water is over the maximum, we remove the excess through shedding.   !
!    After this is checked, we then update the remaining leaf properties, namely the       !
! temperature and liquid water fraction.                                                   !
!------------------------------------------------------------------------------------------!
subroutine adjust_veg_properties(initp,hdid,csite,ipa)
   use rk4_coms             , only : rk4patchtype       & ! structure
                                   , rk4site            & ! intent(in)
                                   , rk4eps             & ! intent(in)
                                   , rk4min_veg_lwater  & ! intent(in)
                                   , hcapcani           & ! intent(in)
                                   , wcapcani           & ! intent(in)
                                   , rk4dry_veg_lwater  & ! intent(in)
                                   , rk4fullveg_lwater  & ! intent(in)
                                   , print_detailed     ! ! intent(in)
   use ed_state_vars        , only : sitetype           & ! structure
                                   , patchtype          ! ! structure
   use ed_misc_coms         , only : fast_diagnostics     ! ! intent(in)
   use consts_coms          , only : cice8              & ! intent(in)
                                   , cliq8              & ! intent(in)
                                   , alvl8              & ! intent(in)
                                   , alvi8              & ! intent(in)
                                   , alli8              & ! intent(in)
                                   , t3ple8             & ! intent(in)
                                   , tsupercool8        & ! intent(in)
                                   , qliqt38            & ! intent(in)
                                   , wdnsi8             & ! intent(in)
                                   , fdnsi8             ! ! intent(in)
   use therm_lib8           , only : qwtk8              ! ! subroutine
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype)     , target     :: initp  ! Integration buffer
   type(sitetype)         , target     :: csite  ! Current site
   integer                , intent(in) :: ipa    ! Current patch ID
   real(kind=8)           , intent(in) :: hdid   ! Time step 
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)        , pointer    :: cpatch
   integer                             :: ico
   integer                             :: ksn
   real(kind=8)                        :: rk4min_leaf_water
   real(kind=8)                        :: rk4dry_leaf_water
   real(kind=8)                        :: rk4wet_leaf_water
   real(kind=8)                        :: veg_wshed
   real(kind=8)                        :: veg_qwshed
   real(kind=8)                        :: veg_dwshed
   real(kind=8)                        :: veg_dew
   real(kind=8)                        :: veg_qdew
   real(kind=8)                        :: veg_boil
   real(kind=8)                        :: veg_qboil
   real(kind=8)                        :: veg_wshed_tot
   real(kind=8)                        :: veg_qwshed_tot
   real(kind=8)                        :: veg_dwshed_tot
   real(kind=8)                        :: veg_dew_tot
   real(kind=8)                        :: veg_qdew_tot
   real(kind=8)                        :: veg_boil_tot
   real(kind=8)                        :: veg_qboil_tot
   real(kind=8)                        :: hdidi
   !---------------------------------------------------------------------------------------!

   cpatch => csite%patch(ipa)
   
   !----- Inverse of time increment -------------------------------------------------------!
   hdidi = 1.d0 / hdid

   !----- Initialise the total shedding. --------------------------------------------------!
   veg_wshed_tot  = 0.d0 
   veg_qwshed_tot = 0.d0
   veg_dwshed_tot = 0.d0
   veg_dew_tot    = 0.d0 
   veg_qdew_tot   = 0.d0
   veg_boil_tot   = 0.d0 
   veg_qboil_tot  = 0.d0

   !----- Looping over cohorts ------------------------------------------------------------!
   cohortloop: do ico=1,cpatch%ncohorts
      !----- Checking whether this is a prognostic cohort... ------------------------------!
      if (initp%solvable(ico)) then
         !---------------------------------------------------------------------------------!
         !   Now we find the TAI-dependent bounds.                                         !
         !---------------------------------------------------------------------------------!
         rk4min_leaf_water = rk4min_veg_lwater * initp%tai(ico)
         rk4dry_leaf_water = rk4dry_veg_lwater * initp%tai(ico)
         rk4wet_leaf_water = rk4fullveg_lwater * initp%tai(ico)

         !---------------------------------------------------------------------------------!
         !    Here we check the bounds for this cohort, and decide what to do in case it   !
         ! is not bounded.                                                                 !
         !---------------------------------------------------------------------------------!
         if (initp%veg_water(ico) < rk4min_leaf_water) then
            !------------------------------------------------------------------------------!
            !    Leaf water is too negative, break it now so the step can be rejected.     !
            !------------------------------------------------------------------------------!
            cycle cohortloop


         elseif (initp%veg_water(ico) > rk4wet_leaf_water) then
            !------------------------------------------------------------------------------!
            !    Too much water over these leaves, we shall shed the excess to the ground. !
            !------------------------------------------------------------------------------!
            veg_wshed  = (initp%veg_water(ico)-rk4wet_leaf_water)
            veg_qwshed = veg_wshed                                                         &
                       * (initp%veg_fliq(ico) * cliq8 * (initp%veg_temp(ico)-tsupercool8)  &
                         + (1.d0-initp%veg_fliq(ico)) * cice8 * initp%veg_temp(ico))
            veg_dwshed = veg_wshed                                                         &
                       * (initp%veg_fliq(ico)*wdnsi8 + (1.d0-initp%veg_fliq(ico))*fdnsi8)
            
            !----- Add the contribution of this cohort to the total shedding. -------------!
            veg_wshed_tot  = veg_wshed_tot  + veg_wshed
            veg_qwshed_tot = veg_qwshed_tot + veg_qwshed
            veg_dwshed_tot = veg_dwshed_tot + veg_dwshed

            !----- Update water mass and energy. ------------------------------------------!
            initp%veg_water(ico)  = initp%veg_water(ico)  - veg_wshed
            initp%veg_energy(ico) = initp%veg_energy(ico) - veg_qwshed



         elseif (initp%veg_water(ico) < rk4dry_leaf_water) then
            !------------------------------------------------------------------------------!
            !    If veg_water is tiny and positive, exchange moisture with the air by      !
            ! donating the total amount as "boiling" (fast evaporation or sublimation).    !
            ! In case the total is tiny but negative, exchange moisture with the air,      !
            ! "stealing" moisture as fast "dew/frost" condensation.                        !
            !------------------------------------------------------------------------------!
            veg_boil  = max(0.d0,  initp%veg_water(ico))
            veg_dew   = max(0.d0,- initp%veg_water(ico))
            veg_qboil = veg_boil * (alvi8 - initp%veg_fliq(ico) * alli8)
            veg_qdew  = veg_dew  * (alvi8 - initp%veg_fliq(ico) * alli8)


            !----- Add the contribution of this cohort to the total boiling. --------------!
            veg_boil_tot  = veg_boil_tot  + veg_boil
            veg_dew_tot   = veg_dew_tot   + veg_dew
            veg_qboil_tot = veg_qboil_tot + veg_qboil
            veg_qdew_tot  = veg_qdew_tot  + veg_qdew

            !----- Updating state variables -----------------------------------------------!
            initp%veg_water(ico)  = 0.d0
            initp%veg_energy(ico) = initp%veg_energy(ico)  + veg_qdew - veg_qboil
         end if
      end if
   end do cohortloop

   !---------------------------------------------------------------------------------------!
   !    The water that fell from the leaves must go somewhere... Here we decide which      !
   ! place is the most suitable.  In case there is already a temporary surface water layer !
   ! we can add the water there, otherwise we dump it into the virtual layer, which may    !
   ! or may not become a temporary surface water layer.                                    !
   !---------------------------------------------------------------------------------------!
   ksn = initp%nlev_sfcwater
   if (ksn > 0) then
      initp%sfcwater_mass(ksn)   = initp%sfcwater_mass(ksn)   + veg_wshed_tot
      initp%sfcwater_energy(ksn) = initp%sfcwater_energy(ksn) + veg_qwshed_tot
      initp%sfcwater_depth(ksn)  = initp%sfcwater_depth(ksn)  + veg_dwshed_tot
   else
      initp%virtual_water        = initp%virtual_water        + veg_wshed_tot
      initp%virtual_heat         = initp%virtual_heat         + veg_qwshed_tot
      initp%virtual_depth        = initp%virtual_depth        + veg_dwshed_tot
   end if

   !----- Update the canopy air specific humidity. ----------------------------------------!
   initp%can_shv  = initp%can_shv + (veg_boil_tot - veg_dew_tot)  * wcapcani


   !----- Updating output fluxes ----------------------------------------------------------!
   if (fast_diagnostics) then
      initp%avg_wshed_vg  = initp%avg_wshed_vg  + veg_wshed_tot                * hdidi
      initp%avg_qwshed_vg = initp%avg_qwshed_vg + veg_qwshed_tot               * hdidi
      initp%avg_vapor_vc  = initp%avg_vapor_vc  + (veg_boil_tot - veg_dew_tot) * hdidi
   end if
   if (print_detailed) then
      initp%flx_wshed_vg  = initp%flx_wshed_vg  + veg_wshed_tot                * hdidi
      initp%flx_qwshed_vg = initp%flx_qwshed_vg + veg_qwshed_tot               * hdidi
      initp%flx_vapor_vc  = initp%flx_vapor_vc  + (veg_boil_tot - veg_dew_tot) * hdidi
   end if
   !---------------------------------------------------------------------------------------!

   return
end subroutine adjust_veg_properties
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
subroutine print_errmax(errmax,yerr,yscal,cpatch,y,ytemp)
   use rk4_coms              , only : rk4patchtype       & ! Structure
                                    , rk4eps             & ! intent(in)
                                    , rk4site            & ! intent(in)
                                    , checkbudget        ! ! intent(in)
   use ed_state_vars         , only : patchtype          ! ! Structure
   use grid_coms             , only : nzg                & ! intent(in)
                                    , nzs                ! ! intent(in)
   implicit none

   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype) , target       :: yerr,yscal,y,ytemp
   type(patchtype)    , target       :: cpatch
   real(kind=8)       , intent(out)  :: errmax
   !----- Local variables -----------------------------------------------------------------!
   integer                           :: ico
   integer                           :: k
   logical                           :: troublemaker
   !----- Constants -----------------------------------------------------------------------!
   character(len=28)  , parameter    :: onefmt = '(a16,1x,3(es12.4,1x),11x,l1)'
   character(len=34)  , parameter    :: lyrfmt = '(a16,1x,i6,1x,3(es12.4,1x),11x,l1)'
   character(len=34)  , parameter    :: cohfmt = '(a16,1x,i6,1x,7(es12.4,1x),11x,l1)'
   !----- Functions -----------------------------------------------------------------------!
   logical            , external     :: large_error
   !---------------------------------------------------------------------------------------!


   write(unit=*,fmt='(80a)'    ) ('=',k=1,80)
   write(unit=*,fmt='(a)'      ) '  ..... PRINTING MAXIMUM ERROR INFORMATION: .....'
   write(unit=*,fmt='(80a)'    ) ('-',k=1,80)
   write(unit=*,fmt='(a)'      ) 
   write(unit=*,fmt='(a)'      ) ' Patch level variables, single layer:'
   write(unit=*,fmt='(80a)'    ) ('-',k=1,80)
   write(unit=*,fmt='(5(a,1x))')  'Name            ','   Max.Error','   Abs.Error'&
                                &,'       Scale','Problem(T|F)'

   errmax       = max(0.0,abs(yerr%can_lntheta/yscal%can_lntheta))
   troublemaker = large_error(yerr%can_theiv,yscal%can_theiv)
   write(unit=*,fmt=onefmt) 'CAN_LNTHETA:',errmax,yerr%can_lntheta,yscal%can_lntheta       &
                                          ,troublemaker

   errmax       = max(errmax,abs(yerr%can_shv/yscal%can_shv))
   troublemaker = large_error(yerr%can_shv,yscal%can_shv)
   write(unit=*,fmt=onefmt) 'CAN_SHV:',errmax,yerr%can_shv,yscal%can_shv,troublemaker

   errmax = max(errmax,abs(yerr%can_co2/yscal%can_co2))
   troublemaker = large_error(yerr%can_co2,yscal%can_co2)
   write(unit=*,fmt=onefmt) 'CAN_CO2:',errmax,yerr%can_co2,yscal%can_co2,troublemaker

   errmax = max(errmax,abs(yerr%can_prss/yscal%can_prss))
   troublemaker = large_error(yerr%can_prss,yscal%can_prss)
   write(unit=*,fmt=onefmt) 'CAN_PRSS:',errmax,yerr%can_prss,yscal%can_prss,troublemaker

   errmax = max(errmax,abs(yerr%virtual_heat/yscal%virtual_heat))
   troublemaker = large_error(yerr%virtual_heat,yscal%virtual_heat)
   write(unit=*,fmt=onefmt) 'VIRTUAL_HEAT:',errmax,yerr%virtual_heat,yscal%virtual_heat    &
                                           ,troublemaker

   errmax = max(errmax,abs(yerr%virtual_water/yscal%virtual_water))
   troublemaker = large_error(yerr%virtual_water,yscal%virtual_water)
   write(unit=*,fmt=onefmt) 'VIRTUAL_WATER:',errmax,yerr%virtual_water,yscal%virtual_water &
                                            ,troublemaker

   write(unit=*,fmt='(80a)') ('-',k=1,80)
   write(unit=*,fmt='(a)'  ) 
   write(unit=*,fmt='(80a)') ('-',k=1,80)
   write(unit=*,fmt='(a)'      ) ' Patch level variables, soil layers:'
   write(unit=*,fmt='(6(a,1x))')  'Name            ',' Level','   Max.Error'               &
                                &,'   Abs.Error','       Scale','Problem(T|F)'

   do k=rk4site%lsl,nzg
      errmax = max(errmax,abs(yerr%soil_water(k)/yscal%soil_water(k)))
      troublemaker = large_error(yerr%soil_water(k),yscal%soil_water(k))
      write(unit=*,fmt=lyrfmt) 'SOIL_WATER:',k,errmax,yerr%soil_water(k)                   &
                                            ,yscal%soil_water(k),troublemaker

      errmax       = max(errmax,abs(yerr%soil_energy(k)/yscal%soil_energy(k)))
      troublemaker = large_error(yerr%soil_energy(k),yscal%soil_energy(k))
      write(unit=*,fmt=lyrfmt) 'SOIL_ENERGY:',k,errmax,yerr%soil_energy(k)                 &
                                             ,yscal%soil_energy(k),troublemaker
   enddo

   if (yerr%nlev_sfcwater > 0) then
      write(unit=*,fmt='(80a)') ('-',k=1,80)
      write(unit=*,fmt='(a)'  ) 
      write(unit=*,fmt='(80a)') ('-',k=1,80)
      write(unit=*,fmt='(a)'      ) ' Patch level variables, water/snow layers:'
      write(unit=*,fmt='(6(a,1x))')  'Name            ',' Level','   Max.Error'      &
                                &,'   Abs.Error','       Scale','Problem(T|F)'
      do k=1,yerr%nlev_sfcwater
         errmax       = max(errmax,abs(yerr%sfcwater_energy(k)/yscal%sfcwater_energy(k)))
         troublemaker = large_error(yerr%sfcwater_energy(k),yscal%sfcwater_energy(k))
         write(unit=*,fmt=lyrfmt) 'SFCWATER_ENERGY:',k,errmax,yerr%sfcwater_energy(k)      &
                                                    ,yscal%sfcwater_energy(k),troublemaker

         errmax       = max(errmax,abs(yerr%sfcwater_mass(k)/yscal%sfcwater_mass(k)))
         troublemaker = large_error(yerr%sfcwater_mass(k),yscal%sfcwater_mass(k))
         write(unit=*,fmt=lyrfmt) 'SFCWATER_MASS:',k,errmax,yerr%sfcwater_mass(k)          &
                                                  ,yscal%sfcwater_mass(k),troublemaker
      end do
   end if

   write(unit=*,fmt='(80a)') ('-',k=1,80)
   write(unit=*,fmt='(a)'  ) 
   write(unit=*,fmt='(80a)') ('-',k=1,80)
   write(unit=*,fmt='(a)'      ) ' Cohort_level variables (only the solvable ones):'
   write(unit=*,fmt='(10(a,1x))')        'Name            ','   PFT','         LAI'        &
                                      ,'         WAI','         WPA','         TAI'        &
                                      ,'   Max.Error','   Abs.Error','       Scale'        &
                                      ,'Problem(T|F)'
   do ico = 1,cpatch%ncohorts
      if (y%solvable(ico)) then
         errmax       = max(errmax,abs(yerr%veg_water(ico)/yscal%veg_water(ico)))
         troublemaker = large_error(yerr%veg_water(ico),yscal%veg_water(ico))
         write(unit=*,fmt=cohfmt) 'VEG_WATER:',cpatch%pft(ico),y%lai(ico),y%wai(ico)       &
                                              ,y%wpa(ico),y%tai(ico),errmax                &
                                              ,yerr%veg_water(ico),yscal%veg_water(ico)    &
                                              ,troublemaker
              

         errmax       = max(errmax,abs(yerr%veg_energy(ico)/yscal%veg_energy(ico)))
         troublemaker = large_error(yerr%veg_energy(ico),yscal%veg_energy(ico))
         write(unit=*,fmt=cohfmt) 'VEG_ENERGY:',cpatch%pft(ico),cpatch%lai(ico),y%wai(ico) &
                                               ,y%wpa(ico),y%tai(ico),errmax               &
                                               ,yerr%veg_energy(ico),yscal%veg_energy(ico) &
                                               ,troublemaker

      end if
   end do

   !---------------------------------------------------------------------------------------!
   !     Here we just need to make sure the user is checking mass, otherwise these         !
   ! variables will not be computed.  If this turns out to be essential, we will make this !
   ! permanent and not dependent on checkbudget.  The only one that is not checked is the  !
   ! runoff, because it is computed only after a step is accepted.                         !
   !---------------------------------------------------------------------------------------!
   if (checkbudget) then
      write(unit=*,fmt='(80a)'    ) ('-',k=1,80)
      write(unit=*,fmt='(a)'      ) 
      write(unit=*,fmt='(a)'      ) ' Budget variables, single layer:'
      write(unit=*,fmt='(80a)'    ) ('-',k=1,80)
      write(unit=*,fmt='(5(a,1x))')  'Name            ','   Max.Error','   Abs.Error'      &
                                   &,'       Scale','Problem(T|F)'
      errmax = max(errmax                                                                  &
                  ,abs(yerr%co2budget_loss2atm/yscal%co2budget_loss2atm))
      troublemaker = large_error(yerr%co2budget_loss2atm                                   &
                                ,yscal%co2budget_loss2atm)
      write(unit=*,fmt=onefmt) 'CO2LOSS2ATM:',errmax,yerr%co2budget_loss2atm               &
                              ,yscal%co2budget_loss2atm,troublemaker

      errmax = max(errmax                                                                  &
                  ,abs(yerr%ebudget_loss2atm/yscal%ebudget_loss2atm))
      troublemaker = large_error(yerr%ebudget_loss2atm                                     &
                                ,yscal%ebudget_loss2atm)
      write(unit=*,fmt=onefmt) 'ENLOSS2ATM:',errmax,yerr%ebudget_loss2atm                  &
                              ,yscal%ebudget_loss2atm,troublemaker

      errmax = max(errmax                                                                  &
                  ,abs(yerr%wbudget_loss2atm/yscal%wbudget_loss2atm))
      troublemaker = large_error(yerr%wbudget_loss2atm                                     &
                                ,yscal%wbudget_loss2atm)
      write(unit=*,fmt=onefmt) 'H2OLOSS2ATM:',errmax,yerr%wbudget_loss2atm                 &
                              ,yscal%wbudget_loss2atm,troublemaker

      errmax = max(errmax,abs( yerr%ebudget_loss2drainage                                  &
                             / yscal%ebudget_loss2drainage))
      troublemaker = large_error(yerr%ebudget_loss2drainage                                &
                                ,yscal%ebudget_loss2drainage)
      write(unit=*,fmt=onefmt) 'ENDRAINAGE:',errmax                                        &
                              ,yerr%ebudget_loss2drainage                                  &
                              ,yscal%ebudget_loss2drainage,troublemaker

      errmax = max(errmax,abs( yerr%wbudget_loss2drainage                                  &
                             / yscal%wbudget_loss2drainage))
      troublemaker = large_error(yerr%wbudget_loss2drainage                                &
                                ,yscal%wbudget_loss2drainage)
      write(unit=*,fmt=onefmt) 'H2ODRAINAGE:',errmax                                       &
                              ,yerr%wbudget_loss2drainage                                  &
                              ,yscal%wbudget_loss2drainage,troublemaker

      errmax = max(errmax                                                                  &
                  ,abs(yerr%co2budget_storage/yscal%co2budget_storage))
      troublemaker = large_error(yerr%co2budget_storage                                    &
                                ,yscal%co2budget_storage)
      write(unit=*,fmt=onefmt) 'CO2STORAGE:',errmax,yerr%co2budget_storage                 &
                              ,yscal%co2budget_storage,troublemaker

      errmax = max(errmax                                                                  &
                  ,abs(yerr%ebudget_storage/yscal%ebudget_storage))
      troublemaker = large_error(yerr%ebudget_storage                                      &
                                ,yscal%ebudget_storage)
      write(unit=*,fmt=onefmt) 'ENSTORAGE:',errmax,yerr%ebudget_storage                    &
                              ,yscal%ebudget_storage,troublemaker

      errmax = max(errmax                                                                  &
                  ,abs(yerr%wbudget_storage/yscal%wbudget_storage))
      troublemaker = large_error(yerr%wbudget_storage                                      &
                                ,yscal%wbudget_storage)
      write(unit=*,fmt=onefmt) 'H2OSTORAGE:',errmax,yerr%wbudget_storage                   &
                              ,yscal%wbudget_storage,troublemaker
   end if

   write(unit=*,fmt='(a)'  ) 
   write(unit=*,fmt='(80a)') ('=',k=1,80)
   write(unit=*,fmt='(a)'  ) 

   return
end subroutine print_errmax
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutine prints the patch and cohort information when the model falls apart... !
!------------------------------------------------------------------------------------------!
subroutine print_csiteipa(csite, ipa)
   use rk4_coms              , only : rk4site       ! ! intent(in)
   use ed_state_vars         , only : sitetype      & ! structure
                                    , patchtype     ! ! structure
   use ed_misc_coms          , only : current_time  ! ! intent(in)
   use grid_coms             , only : nzs           & ! intent(in)
                                    , nzg           ! ! intent(in)
   use ed_max_dims           , only : n_pft         ! ! intent(in)
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   type(sitetype)  , target     :: csite
   integer         , intent(in) :: ipa
   !----- Local variable ------------------------------------------------------------------!
   type(patchtype) , pointer    :: cpatch
   integer                      :: ico 
   integer                      :: k   
   !---------------------------------------------------------------------------------------!

   cpatch => csite%patch(ipa)

   write(unit=*,fmt='(80a)') ('=',k=1,80)
   write(unit=*,fmt='(80a)') ('=',k=1,80)

   write(unit=*,fmt='(a)')  ' |||| Printing PATCH information (csite) ||||'

   write(unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(a,1x,2(i2.2,a),i4.4,1x,f12.0,1x,a)')                                &
         'Time:',current_time%month,'/',current_time%date,'/',current_time%year            &
                ,current_time%time,'UTC'
   write(unit=*,fmt='(a,1x,es12.4)') 'Attempted step size:',csite%htry(ipa)
   write (unit=*,fmt='(a,1x,i6)')    'Ncohorts: ',cpatch%ncohorts
 
   write (unit=*,fmt='(80a)') ('-',k=1,80)
   write (unit=*,fmt='(a)'  ) 'Cohort information (only the solvable ones shown): '
   write (unit=*,fmt='(80a)') ('-',k=1,80)
   write (unit=*,fmt='(2(a7,1x),11(a12,1x))')                                              &
         '    PFT','KRDEPTH','      NPLANT','         LAI','         DBH','       BDEAD'   &
                           &,'      BALIVE','  VEG_ENERGY','    VEG_TEMP','   VEG_WATER'   &
                           &,'     FS_OPEN','         FSW','         FSN'
   do ico = 1,cpatch%ncohorts
      if (cpatch%solvable(ico)) then
         write(unit=*,fmt='(2(i7,1x),11(es12.4,1x))') cpatch%pft(ico), cpatch%krdepth(ico) &
              ,cpatch%nplant(ico),cpatch%lai(ico),cpatch%dbh(ico),cpatch%bdead(ico)        &
              ,cpatch%balive(ico),cpatch%veg_energy(ico),cpatch%veg_temp(ico)              &
              ,cpatch%veg_water(ico),cpatch%fs_open(ico),cpatch%fsw(ico),cpatch%fsn(ico)
      end if
   end do
   write (unit=*,fmt='(a)'  ) ' '
   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(7(a12,1x))')  '   DIST_TYPE','         AGE','        AREA'          &
                                    ,'          RH','AVGDAILY_TMP','     SUM_CHD'          &
                                    ,'     SUM_DGD'
   write (unit=*,fmt='(i12,1x,6(es12.4,1x))')  csite%dist_type(ipa),csite%age(ipa)         &
         ,csite%area(ipa),csite%rh(ipa),csite%avg_daily_temp(ipa),csite%sum_chd(ipa)       &
         ,csite%sum_dgd(ipa)

   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(6(a12,1x))')  '  VEG_HEIGHT','   VEG_ROUGH','         LAI'          &
                                    ,'        HTRY','    CAN_RHOS','   CAN_DEPTH'
   write (unit=*,fmt='(6(es12.4,1x))') csite%veg_height(ipa),csite%veg_rough(ipa)          &
                                      ,csite%lai(ipa),csite%htry(ipa)                      &
                                      ,csite%can_rhos(ipa),csite%can_depth(ipa)

   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(5(a12,1x))')  '   CAN_THEIV','    CAN_TEMP','     CAN_SHV'          &
                                    ,'    CAN_PRSS','     CAN_CO2'
   write (unit=*,fmt='(5(es12.4,1x))') csite%can_theiv(ipa),csite%can_temp(ipa)            &
                                      ,csite%can_shv(ipa)  ,csite%can_prss(ipa)            &
                                      ,csite%can_co2(ipa)

   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(9(a12,1x))')  '       USTAR','       QSTAR','       CSTAR'          &
                                    ,'       TSTAR','        ZETA','     RI_BULK'          &
                                    ,'     RLONG_G','    RSHORT_G','     RLONG_S'
   write (unit=*,fmt='(9(es12.4,1x))') csite%ustar(ipa),csite%qstar(ipa),csite%cstar(ipa)  &
                                      ,csite%tstar(ipa),csite%zeta(ipa),csite%ribulk(ipa)  &
                                      ,csite%rlong_g(ipa),csite%rshort_g(ipa)              &
                                      ,csite%rlong_s(ipa)

   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(a5,1x,a12)') '  PFT','       REPRO'
   do k=1,n_pft
      write (unit=*,fmt='(i5,1x,es12.4)') k,csite%repro(k,ipa)
   end do

   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(a5,1x,5(a12,1x))')   '  KZG','  NTEXT_SOIL',' SOIL_ENERGY'          &
                                   &,'  SOIL_TEMPK','  SOIL_WATER','SOIL_FRACLIQ'
   do k=rk4site%lsl,nzg
      write (unit=*,fmt='(i5,1x,i12,4(es12.4,1x))') k,csite%ntext_soil(k,ipa)              &
            ,csite%soil_energy(k,ipa),csite%soil_tempk(k,ipa),csite%soil_water(k,ipa)      &
            ,csite%soil_fracliq(k,ipa)
   end do
   
   if (csite%nlev_sfcwater(ipa) >= 1) then
      write (unit=*,fmt='(80a)') ('-',k=1,80)
      write (unit=*,fmt='(a5,1x,6(a12,1x))')   '  KZS',' SFCW_ENERGY','  SFCW_TEMPK'       &
                                      &,'   SFCW_MASS','SFCW_FRACLIQ','  SFCW_DEPTH'       &
                                      &,'    RSHORT_S'
      do k=1,csite%nlev_sfcwater(ipa)
         write (unit=*,fmt='(i5,1x,6(es12.4,1x))') k,csite%sfcwater_energy(k,ipa)          &
               ,csite%sfcwater_tempk(k,ipa),csite%sfcwater_mass(k,ipa)                     &
               ,csite%sfcwater_fracliq(k,ipa),csite%sfcwater_depth(k,ipa)                  &
               ,csite%rshort_s(k,ipa)
      end do
   end if

   write(unit=*,fmt='(80a)') ('=',k=1,80)
   write(unit=*,fmt='(80a)') ('=',k=1,80)
   write(unit=*,fmt='(a)'  ) ' '
   return
end subroutine print_csiteipa
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!    This subroutine is similar to print_csite, except that it also prints the             !
! outcome of the Runge-Kutta integrator.                                                   !
!------------------------------------------------------------------------------------------!
subroutine print_rk4patch(y,csite,ipa)
   use rk4_coms              , only : rk4patchtype          & ! structure
                                    , rk4site               & ! intent(in)
                                    , rk4tiny_sfcw_mass     ! ! intent(in)
   use ed_state_vars         , only : sitetype              & ! structure
                                    , patchtype             ! ! structure
   use grid_coms             , only : nzg                   & ! intent(in)
                                    , nzs                   ! ! intent(in)
   use ed_misc_coms             , only : current_time          ! ! intent(in)
   use therm_lib8            , only : qtk8                  & ! subroutine
                                    , qwtk8                 ! ! subroutine
   implicit none
   !----- Arguments -----------------------------------------------------------------------!
   type(rk4patchtype) , target     :: y
   type(sitetype)     , target     :: csite
   integer            , intent(in) :: ipa
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)    , pointer    :: cpatch
   integer                         :: k
   integer                         :: ico
   real(kind=8)                    :: virtual_temp, virtual_fliq
   !---------------------------------------------------------------------------------------!

   cpatch => csite%patch(ipa)

   write(unit=*,fmt='(80a)') ('=',k=1,80)
   write(unit=*,fmt='(80a)') ('=',k=1,80)

   write(unit=*,fmt='(a)')  ' |||| Printing PATCH information (rk4patch) ||||'

   write(unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(a,1x,2(i2.2,a),i4.4,1x,f12.0,1x,a)')                                &
         'Time:',current_time%month,'/',current_time%date,'/',current_time%year            &
                ,current_time%time,'s'
   write(unit=*,fmt='(a,1x,es12.4)') 'Attempted step size:',csite%htry(ipa)
   write (unit=*,fmt='(a,1x,i6)')    'Ncohorts: ',cpatch%ncohorts
   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(80a)')         ('-',k=1,80)
   write (unit=*,fmt='(a)')           ' ATMOSPHERIC CONDITIONS: '
   write (unit=*,fmt='(a,1x,es12.4)') ' Air temperature     : ',rk4site%atm_tmp
   write (unit=*,fmt='(a,1x,es12.4)') ' Air potential temp. : ',rk4site%atm_theta
   write (unit=*,fmt='(a,1x,es12.4)') ' Air theta_Eiv       : ',rk4site%atm_theiv
   write (unit=*,fmt='(a,1x,es12.4)') ' H2Ov mixing ratio   : ',rk4site%atm_shv
   write (unit=*,fmt='(a,1x,es12.4)') ' CO2  mixing ratio   : ',rk4site%atm_co2
   write (unit=*,fmt='(a,1x,es12.4)') ' Pressure            : ',rk4site%atm_prss
   write (unit=*,fmt='(a,1x,es12.4)') ' Exner function      : ',rk4site%atm_exner
   write (unit=*,fmt='(a,1x,es12.4)') ' Wind speed          : ',rk4site%vels
   write (unit=*,fmt='(a,1x,es12.4)') ' Height              : ',rk4site%geoht
   write (unit=*,fmt='(a,1x,es12.4)') ' Precip. mass  flux  : ',rk4site%pcpg
   write (unit=*,fmt='(a,1x,es12.4)') ' Precip. heat  flux  : ',rk4site%qpcpg
   write (unit=*,fmt='(a,1x,es12.4)') ' Precip. depth flux  : ',rk4site%dpcpg

   write (unit=*,fmt='(80a)') ('=',k=1,80)
   write (unit=*,fmt='(a)'  ) 'Cohort information (only those solvable are shown): '
   write (unit=*,fmt='(80a)') ('-',k=1,80)
   write (unit=*,fmt='(2(a7,1x),8(a12,1x))')                                               &
         '    PFT','KRDEPTH','      NPLANT','        HITE','         DBH','       BDEAD'   &
                           &,'      BALIVE','     FS_OPEN','         FSW','         FSN'
   do ico = 1,cpatch%ncohorts
      if (cpatch%solvable(ico)) then
         write(unit=*,fmt='(2(i7,1x),8(es12.4,1x))') cpatch%pft(ico), cpatch%krdepth(ico)  &
              ,cpatch%nplant(ico),cpatch%hite(ico),cpatch%dbh(ico),cpatch%bdead(ico)       &
              ,cpatch%balive(ico),cpatch%fs_open(ico),cpatch%fsw(ico),cpatch%fsn(ico)
      end if
   end do
   write (unit=*,fmt='(80a)') ('-',k=1,80)
   write (unit=*,fmt='(2(a7,1x),8(a12,1x))')                                               &
         '    PFT','KRDEPTH','         LAI','         WPA','         TAI','  VEG_ENERGY'   &
             ,'   VEG_WATER','    VEG_HCAP','    VEG_TEMP','    VEG_FLIQ'
   do ico = 1,cpatch%ncohorts
      if (y%solvable(ico)) then
         write(unit=*,fmt='(2(i7,1x),9(es12.4,1x))') cpatch%pft(ico), cpatch%krdepth(ico)  &
               ,y%lai(ico),y%wpa(ico),y%tai(ico),y%veg_energy(ico),y%veg_water(ico)        &
               ,y%hcapveg(ico),y%veg_temp(ico),y%veg_fliq(ico)
      end if
   end do
   write (unit=*,fmt='(80a)') ('=',k=1,80)
   write (unit=*,fmt='(a)'  ) ' '
   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(7(a12,1x))')   '  VEG_HEIGHT','   VEG_ROUGH','   PATCH_LAI'         &
                                     ,'    CAN_RHOS','   CAN_DEPTH','     CAN_CO2'         &
                                     ,'    CAN_PRSS'
                                     
   write (unit=*,fmt='(7(es12.4,1x))') csite%veg_height(ipa),csite%veg_rough(ipa)          &
                                      ,csite%lai(ipa),y%can_rhos,y%can_depth,y%can_co2     &
                                      ,y%can_prss
   write (unit=*,fmt='(80a)') ('-',k=1,80)
   write (unit=*,fmt='(7(a12,1x))')  '   CAN_THEIV','   CAN_THETA','    CAN_TEMP'          &
                                    ,'     CAN_SHV','     CAN_SSH','    CAN_RVAP'          &
                                    ,'     CAN_RHV'
                                     
                                     
   write (unit=*,fmt='(7(es12.4,1x))')   y%can_theiv, y%can_theta, y%can_temp              &
                                       , y%can_shv  , y%can_ssh  , y%can_rvap              &
                                       , y%can_rhv
                                       

   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(7(a12,1x))')  '       USTAR','       QSTAR','       CSTAR'          &
                                    ,'       TSTAR','       ESTAR','        ZETA'          &
                                    ,'     RI_BULK'
   write (unit=*,fmt='(7(es12.4,1x))') y%ustar,y%qstar,y%cstar,y%tstar,y%estar,y%zeta      &
                                      ,y%ribulk

   write (unit=*,fmt='(80a)') ('-',k=1,80)
   if (y%virtual_water /= 0.) then
      call qtk8(y%virtual_heat/y%virtual_water,virtual_temp,virtual_fliq)
   else
      virtual_temp = y%soil_tempk(nzg)
      virtual_fliq = y%soil_fracliq(nzg)
   end if


   write (unit=*,fmt='(5(a12,1x))')  'VIRTUAL_FLAG','VIRTUAL_HEAT','  VIRT_WATER'          &
                                   &,'VIRTUAL_TEMP','VIRTUAL_FLIQ'
   write (unit=*,fmt='(i12,1x,4(es12.4,1x))') y%virtual_flag,y%virtual_heat                &
                                             ,y%virtual_water,virtual_temp,virtual_fliq
   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(4(a12,1x))')    '  GROUND_SHV',' SURFACE_SSH','SURFACE_TEMP'        &
                                      ,'SURFACE_FLIQ'
   write (unit=*,fmt='(4(es12.4,1x))') y%ground_shv, y%surface_ssh, y%surface_temp         &
                                      ,y%surface_fliq

   write (unit=*,fmt='(80a)') ('-',k=1,80)

   write (unit=*,fmt='(a5,1x,5(a12,1x))')   '  KZG','  NTEXT_SOIL',' SOIL_ENERGY'          &
                                   &,'  SOIL_TEMPK','  SOIL_WATER','SOIL_FRACLIQ'
   do k=rk4site%lsl,nzg
      write (unit=*,fmt='(i5,1x,i12,4(es12.4,1x))') k,csite%ntext_soil(k,ipa)              &
            ,y%soil_energy(k),y%soil_tempk(k),y%soil_water(k),y%soil_fracliq(k)
   end do
   
   if (csite%nlev_sfcwater(ipa) >= 1) then
      write (unit=*,fmt='(80a)') ('-',k=1,80)
      write (unit=*,fmt='(a5,1x,5(a12,1x))')   '  KZS',' SFCW_ENERGY','  SFCW_TEMPK'       &
                                      &,'   SFCW_MASS','SFCW_FRACLIQ','  SFCW_DEPTH'
      do k=1,csite%nlev_sfcwater(ipa)
         write (unit=*,fmt='(i5,1x,5(es12.4,1x))') k,y%sfcwater_energy(k)                  &
               ,y%sfcwater_tempk(k),y%sfcwater_mass(k),y%sfcwater_fracliq(k)               &
               ,y%sfcwater_depth(k)
      end do
   end if

   write(unit=*,fmt='(80a)') ('=',k=1,80)
   write(unit=*,fmt='(80a)') ('=',k=1,80)
   write(unit=*,fmt='(a)'  ) ' '

   !----- Printing the corresponding patch information (with some redundancy) -------------!
   call print_csiteipa(csite, ipa)

   call fatal_error('IFLAG1 problem. The model didn''t converge!','print_rk4patch'&
                 &,'rk4_integ_utils.f90')
   return
end subroutine print_rk4patch
!==========================================================================================!
!==========================================================================================!






!==========================================================================================!
!==========================================================================================!
!     This sub-routine prints the full state of a given patch, for full debugging          !
! purposes.  This will create one file for each patch.  This sub-routine will not print    !
! the temperature of each cohort, instead it will just compute the average.                !
!------------------------------------------------------------------------------------------!
subroutine print_rk4_state(initp,fluxp,csite,ipa,elapsed,hdid)
   use consts_coms  , only : t3ple8        ! ! intent(in)
   use ed_max_dims  , only : str_len       ! ! intent(in)
   use ed_misc_coms , only : current_time  ! ! intent(in)
   use ed_state_vars, only : sitetype      & ! structure
                           , patchtype     ! ! structure
   use grid_coms    , only : nzg           & ! intent(in)
                           , nzs           ! ! intent(in)
   use rk4_coms     , only : rk4patchtype  & ! structure
                           , rk4site       & ! intent(in)
                           , detail_pref   ! ! intent(in)
   use therm_lib8   , only : qwtk8         ! ! sub-routine
   use soil_coms    , only : soil8         ! ! intent(in)
   implicit none
   !----- Arguments. ----------------------------------------------------------------------!
   type(rk4patchtype)    , target     :: initp
   type(rk4patchtype)    , target     :: fluxp
   type(sitetype)        , target     :: csite
   integer               , intent(in) :: ipa
   real(kind=8)          , intent(in) :: elapsed
   real(kind=8)          , intent(in) :: hdid
   !----- Local variables -----------------------------------------------------------------!
   type(patchtype)       , pointer    :: cpatch
   character(len=str_len)             :: detail_fout
   integer                            :: k
   integer                            :: nsoil
   integer                            :: ico
   logical                            :: isthere
   real(kind=8)                       :: sum_veg_energy
   real(kind=8)                       :: sum_veg_water
   real(kind=8)                       :: sum_hcapveg
   real(kind=8)                       :: sum_gpp
   real(kind=8)                       :: sum_plresp
   real(kind=8)                       :: soil_rh
   real(kind=8)                       :: avg_veg_temp
   real(kind=8)                       :: avg_veg_fliq
   real(kind=8)                       :: sfc_temp
   real(kind=8)                       :: elapsec
   !----- Local constants. ----------------------------------------------------------------!
   character(len=10), parameter :: hfmt='(62(a,1x))'
   character(len=48), parameter :: bfmt='(3(i13,1x),2(es13.6,1x),2(i13,1x),55(es13.6,1x))'
   !---------------------------------------------------------------------------------------!


   !---------------------------------------------------------------------------------------!
   !     First we loop over all cohorts and add the vegetation energy and water.           !
   !---------------------------------------------------------------------------------------!
   sum_veg_energy = 0.d0
   sum_veg_water  = 0.d0
   sum_hcapveg    = 0.d0
   sum_gpp        = 0.d0
   sum_plresp     = 0.d0
   soil_rh        = initp%rh-initp%cwd_rh
   cpatch => csite%patch(ipa)
   do ico=1,cpatch%ncohorts
      if (initp%solvable(ico)) then
         sum_veg_energy = sum_veg_energy + initp%veg_energy(ico)
         sum_veg_water  = sum_veg_water  + initp%veg_water(ico)
         sum_hcapveg    = sum_hcapveg    + initp%hcapveg(ico)
         sum_gpp        = sum_gpp        + initp%gpp(ico)
         sum_plresp     = sum_plresp     + initp%leaf_resp(ico)                            &
                                         + initp%root_resp(ico)                            &
                                         + initp%growth_resp(ico)                          &
                                         + initp%storage_resp(ico)                         &
                                         + initp%vleaf_resp(ico)
      end if
   end do
   !---------------------------------------------------------------------------------------!

   !---------------------------------------------------------------------------------------!
   !     Then we find the average cohort temperature.  If none of the cohorts were solved, !
   ! of if there is no vegetation, we assign the canopy air temperature.                   !
   !---------------------------------------------------------------------------------------!
   if (sum_veg_energy == 0.d0) then
      avg_veg_temp = initp%can_temp
      if (initp%can_temp == t3ple8) then
         avg_veg_fliq = 5.d-1
      elseif (initp%can_temp > t3ple8) then
         avg_veg_fliq = 1.d0
      else
         avg_veg_fliq = 0.d0
      end if
   else
      call qwtk8(sum_veg_energy,sum_veg_water,sum_hcapveg,avg_veg_temp,avg_veg_fliq)
   end if
   !---------------------------------------------------------------------------------------!


   !----- Compute the hour as elapsed seconds since midnight. -----------------------------!
   elapsec = dble(current_time%time) + elapsed
   !---------------------------------------------------------------------------------------!


   !----- Find the soil type of the top layer. --------------------------------------------!
   nsoil   = csite%ntext_soil(nzg,ipa)
   !---------------------------------------------------------------------------------------!



   !----- Create the file name. -----------------------------------------------------------!
   write (detail_fout,fmt='(a,i4.4,a)') trim(detail_pref),ipa,'.txt'
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !    Check whether the file exists or not.  In case it doesn't, create it and add the   !
   ! header.                                                                               !
   !---------------------------------------------------------------------------------------!
   inquire(file=trim(detail_fout),exist=isthere)
   if (.not. isthere) then
      open  (unit=83,file=trim(detail_fout),status='replace',action='write')
      write (unit=83,fmt=hfmt)   '         YEAR', '        MONTH', '          DAY'         &
                               , '         TIME', '         HDID', '          KSN'         &
                               , '  FLAG.WFLXGC', '     ATM.PRSS', '     ATM.TEMP'         &
                               , '      ATM.SHV', '      ATM.CO2', '     ATM.VELS'         &
                               , '    ATM.PRATE', '   ATM.HEIGHT', '     ATM.RHOS'         &
                               , '   ATM.RELHUM', '    ATM.THETA', '    ATM.THEIV'         &
                               , '   MET.RSHORT', '    MET.RLONG', '     CAN.PRSS'         &
                               , '     CAN.TEMP', '      CAN.SHV', '      CAN.CO2'         &
                               , '    CAN.DEPTH', '     CAN.RHOS', '   CAN.RELHUM'         &
                               , '    CAN.THETA', '    CAN.THEIV', '     SFC.TEMP'         &
                               , '      SFC.SHV', '     VEG.TEMP', '    VEG.WATER'         &
                               , '    SOIL.TEMP', '   SOIL.WATER', '       SOILCP'         &
                               , '       SOILWP', '       SOILFC', '       SLMSTS'         &
                               , '        USTAR', '        TSTAR', '        QSTAR'         &
                               , '        CSTAR', '         ZETA', '      RI_BULK'         &
                               , '       NETRAD', '       WFLXVC', '       DEWGND'         &
                               , '       WFLXGC', '       WFLXAC', '       TRANSP'         &
                               , '        WSHED', '    INTERCEPT', '  THROUGHFALL'         &
                               , '       HFLXGC', '       HFLXVC', '       HFLXAC'         &
                               , '       CFLXAC', '        CWDRH', '       SOILRH'         &
                               , '          GPP', '       PLRESP'
      close (unit=83,status='keep')
   end if
   !---------------------------------------------------------------------------------------!



   !---------------------------------------------------------------------------------------!
   !     Re-open the file at the last line, and include the current status.                !
   !---------------------------------------------------------------------------------------!
   open (unit=83,file=trim(detail_fout),status='old',action='write',position='append')
   write(unit=83,fmt=bfmt)                                                                 &
                     current_time%year     , current_time%month    , current_time%date     &
                   , elapsec               , hdid                  , initp%nlev_sfcwater   &
                   , initp%flag_wflxgc     , rk4site%atm_prss      , rk4site%atm_tmp       &
                   , rk4site%atm_shv       , rk4site%atm_co2       , rk4site%vels          &
                   , rk4site%pcpg          , rk4site%geoht         , rk4site%rhos          &
                   , rk4site%atm_rhv       , rk4site%atm_theta     , rk4site%atm_theiv     &
                   , rk4site%rshort        , rk4site%rlong         , initp%can_prss        &
                   , initp%can_temp        , initp%can_shv         , initp%can_co2         &
                   , initp%can_depth       , initp%can_rhos        , initp%can_rhv         &
                   , initp%can_theta       , initp%can_theiv       , initp%surface_temp    &
                   , initp%ground_shv      , avg_veg_temp          , sum_veg_water         &
                   , initp%soil_tempk(nzg) , initp%soil_water(nzg) , soil8(nsoil)%soilcp   &
                   , soil8(nsoil)%soilwp   , soil8(nsoil)%sfldcap  , soil8(nsoil)%slmsts   &
                   , initp%ustar           , initp%tstar           , initp%qstar           &
                   , initp%cstar           , initp%zeta            , initp%ribulk          &
                   , fluxp%flx_netrad      , fluxp%flx_vapor_vc    , fluxp%flx_dew_cg      &
                   , fluxp%flx_vapor_gc    , fluxp%flx_vapor_ac    , fluxp%flx_transp      &
                   , fluxp%flx_wshed_vg    , fluxp%flx_intercepted , fluxp%flx_throughfall &
                   , fluxp%flx_sensible_gc , fluxp%flx_sensible_vc , fluxp%flx_sensible_ac &
                   , fluxp%flx_carbon_ac   , initp%cwd_rh          , soil_rh               &
                   , sum_gpp               , sum_plresp            
   close(unit=83,status='keep')
   !---------------------------------------------------------------------------------------!
   return
end subroutine print_rk4_state
!==========================================================================================!
!==========================================================================================!
