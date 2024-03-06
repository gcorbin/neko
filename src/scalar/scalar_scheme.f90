! Copyright (c) 2022-2024, The Neko Authors
! All rights reserved.
!
! Redistribution and use in source and binary forms, with or without
! modification, are permitted provided that the following conditions
! are met:
!
!   * Redistributions of source code must retain the above copyright
!     notice, this list of conditions and the following disclaimer.
!
!   * Redistributions in binary form must reproduce the above
!     copyright notice, this list of conditions and the following
!     disclaimer in the documentation and/or other materials provided
!     with the distribution.
!
!   * Neither the name of the authors nor the names of its
!     contributors may be used to endorse or promote products derived
!     from this software without specific prior written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
! "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
! LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
! FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
! COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
! INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
! BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
! LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
! CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
! LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
! ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
! POSSIBILITY OF SUCH DAMAGE.
!
!> Contains the scalar_scheme_t type.

! todo: module name
module scalar_scheme
  use gather_scatter, only : gs_t
  use checkpoint, only : chkp_t
  use num_types, only: rp
  use field, only : field_t
  use space, only : space_t
  use dofmap, only :  dofmap_t
  use krylov, only : ksp_t
  use coefs, only : coef_t
  use dirichlet, only : dirichlet_t
  use neumann, only : neumann_t
  use krylov_fctry, only : krylov_solver_factory, krylov_solver_destroy
  use jacobi, only : jacobi_t
  use device_jacobi, only : device_jacobi_t
  use sx_jacobi, only : sx_jacobi_t
  use hsmg, only : hsmg_t
  use precon_fctry, only : precon_factory, pc_t, precon_destroy
  use bc, only : bc_t, bc_list_t, bc_list_free, bc_list_init, &
                 bc_list_apply_scalar, bc_list_add
  use mesh, only : mesh_t, NEKO_MSH_MAX_ZLBLS
  use facet_zone, only : facet_zone_t
  use time_scheme_controller, only : time_scheme_controller_t
  use logger, only : neko_log, LOG_SIZE
  use field_registry, only : neko_field_registry
  use usr_scalar, only : usr_scalar_t, usr_scalar_bc_eval
  use json_utils, only : json_get, json_get_or_default
  use json_module, only : json_file
  use user_intf, only : user_t
  use material_properties, only : material_properties_t
  use utils, only : neko_error
  use scalar_source_term, only : scalar_source_term_t
  use field_series
  implicit none

  !> Base type for a scalar advection-diffusion solver.
  type, abstract :: scalar_scheme_t
     !> x-component of Velocity
     type(field_t), pointer :: u
     !> y-component of Velocity
     type(field_t), pointer :: v
     !> z-component of Velocity
     type(field_t), pointer :: w
     !> The scalar.
     type(field_t), pointer :: s
     !> Lag arrays, i.e. solutions at previous timesteps.
     type(field_series_t) :: slag
     !> Function space \f$ X_h \f$.
     type(space_t), pointer :: Xh
     !> Dofmap associated with \f$ X_h \f$.
     type(dofmap_t), pointer :: dm_Xh
     !> Gather-scatter associated with \f$ X_h \f$.
     type(gs_t), pointer :: gs_Xh
     !> Coefficients associated with \f$ X_h \f$.
     type(coef_t), pointer  :: c_Xh
     !> Right-hand side.
     type(field_t), pointer :: f_Xh => null()
     !> The source term for equation.
     type(scalar_source_term_t) :: source_term
     !> Krylov solver.
     class(ksp_t), allocatable  :: ksp
     !> Max iterations in the Krylov solver.
     integer :: ksp_maxiter
     !> Projection space size.
     integer :: projection_dim
     !> Preconditioner.
     class(pc_t), allocatable :: pc
     !> Dirichlet conditions.
     type(dirichlet_t) :: dir_bcs(NEKO_MSH_MAX_ZLBLS)
     !> Neumann conditions.
     type(neumann_t) :: neumann_bcs(NEKO_MSH_MAX_ZLBLS)
     !> User Dirichlet conditions.
     type(usr_scalar_t) :: user_bc
     !> Number of Dirichlet bcs.
     integer :: n_dir_bcs = 0
     !> Number of Neumann bcs.
     integer :: n_neumann_bcs = 0
     !> List of Dirichlet boundary conditions, including the user one.
     type(bc_list_t) :: bclst_dirichlet
     !> List of Neumann conditions list
     type(bc_list_t) :: bclst_neumann
     !> Case paramters.
     type(json_file), pointer :: params
     !> Mesh.
     type(mesh_t), pointer :: msh => null()
     !> Checkpoint for restarts.
     type(chkp_t) :: chkp
     !> Thermal diffusivity.
     real(kind=rp), pointer :: lambda
     !> Density.
     real(kind=rp), pointer :: rho
     !> Specific heat capacity.
     real(kind=rp), pointer :: cp
     !> Boundary condition labels (if any)
     character(len=20), allocatable :: bc_labels(:)
   contains
     !> Constructor for the base type.
     procedure, pass(this) :: scheme_init => scalar_scheme_init
     !> Destructor for the base type.
     procedure, pass(this) :: scheme_free => scalar_scheme_free
     !> Validate successful initialization.
     procedure, pass(this) :: validate => scalar_scheme_validate
     !> Assings the evaluation function for  `user_bc`.
     procedure, pass(this) :: set_user_bc => scalar_scheme_set_user_bc
     !> Constructor.
     procedure(scalar_scheme_init_intrf), pass(this), deferred :: init
     !> Destructor.
     procedure(scalar_scheme_free_intrf), pass(this), deferred :: free
     !> Solve for the current timestep.
     procedure(scalar_scheme_step_intrf), pass(this), deferred :: step
     !> Restart from a checkpoint.
     procedure(scalar_scheme_restart_intrf), pass(this), deferred :: restart
  end type scalar_scheme_t

  !> Abstract interface to initialize a scalar formulation
  abstract interface
     subroutine scalar_scheme_init_intrf(this, msh, coef, gs, params, user,&
                                         material_properties)
       import scalar_scheme_t
       import json_file
       import coef_t
       import gs_t
       import mesh_t
       import user_t
       import material_properties_t
       class(scalar_scheme_t), target, intent(inout) :: this
       type(mesh_t), target, intent(inout) :: msh
       type(coef_t), target, intent(inout) :: coef
       type(gs_t), target, intent(inout) :: gs
       type(json_file), target, intent(inout) :: params
       type(user_t), target, intent(in) :: user
       type(material_properties_t), intent(inout) :: material_properties
     end subroutine scalar_scheme_init_intrf
  end interface

  !> Abstract interface to restart a scalar formulation
  abstract interface
     subroutine scalar_scheme_restart_intrf(this, dtlag, tlag)
       import scalar_scheme_t
       import chkp_t
       import rp
       class(scalar_scheme_t), target, intent(inout) :: this
       real(kind=rp) :: dtlag(10), tlag(10)
     end subroutine scalar_scheme_restart_intrf
  end interface

  !> Abstract interface to dealocate a scalar formulation
  abstract interface
     subroutine scalar_scheme_free_intrf(this)
       import scalar_scheme_t
       class(scalar_scheme_t), intent(inout) :: this
     end subroutine scalar_scheme_free_intrf
  end interface

  !> Abstract interface to compute a time-step
  abstract interface
     subroutine scalar_scheme_step_intrf(this, t, tstep, dt, ext_bdf)
       import scalar_scheme_t
       import time_scheme_controller_t
       import rp
       class(scalar_scheme_t), intent(inout) :: this
       real(kind=rp), intent(inout) :: t
       integer, intent(inout) :: tstep
       real(kind=rp), intent(in) :: dt
       type(time_scheme_controller_t), intent(inout) :: ext_bdf
     end subroutine scalar_scheme_step_intrf
  end interface

contains

  !> Initialize boundary conditions
  !! @param zones List of zones
  !! @param bc_labels List of user specified bcs from the parameter file
  !! currently dirichlet 'd=X' and 'user' supported
  subroutine scalar_scheme_add_bcs(this, zones, bc_labels)
    class(scalar_scheme_t), intent(inout) :: this
    type(facet_zone_t), intent(inout) :: zones(NEKO_MSH_MAX_ZLBLS)
    character(len=20), intent(in) :: bc_labels(:)
    character(len=20) :: bc_label
    integer :: i, j, bc_idx
    real(kind=rp) :: dir_value, flux_value
    logical :: bc_exists

    do i = 1, size(bc_labels)
       bc_label = trim(bc_labels(i))
       if (bc_label(1:2) .eq. 'd=') then
! The idea of this commented piece of code is to merge bcs with the same
! Dirichlet value into 1 so that one has less kernel launches. Currently
! segfaults, needs investigation.
!          bc_exists = .false.
!          bc_idx = 0
!          do j = 1, i-1
!             if (bc_label .eq. bc_labels(j)) then
!                bc_exists = .true.
!                bc_idx = j
!             end if
!          end do

!          if (bc_exists) then
!             call this%dir_bcs(j)%mark_zone(zones(i))
!          else
          this%n_dir_bcs = this%n_dir_bcs + 1
          call this%dir_bcs(this%n_dir_bcs)%init(this%dm_Xh)
          call this%dir_bcs(this%n_dir_bcs)%mark_zone(zones(i))
          read(bc_label(3:), *) dir_value
          call this%dir_bcs(this%n_dir_bcs)%set_g(dir_value)
!          end if
       end if

       if (bc_label(1:2) .eq. 'n=') then
          this%n_neumann_bcs = this%n_neumann_bcs + 1
          call this%neumann_bcs(this%n_neumann_bcs)%init(this%dm_Xh)
          call this%neumann_bcs(this%n_neumann_bcs)%mark_zone(zones(i))
          read(bc_label(3:), *) flux_value
          call this%neumann_bcs(this%n_neumann_bcs)%init_neumann(flux_value,&
                                                                 this%c_Xh)
       end if

       !> Check if user bc on this zone
       if (bc_label(1:4) .eq. 'user') then
          call this%user_bc%mark_zone(zones(i))
       end if
    end do

    do i = 1, this%n_dir_bcs
       call this%dir_bcs(i)%finalize()
       call bc_list_add(this%bclst_dirichlet, this%dir_bcs(i))
    end do

    ! Create list with just Neumann bcs
    call bc_list_init(this%bclst_neumann, this%n_neumann_bcs)
    do i=1, this%n_neumann_bcs
       call this%neumann_bcs(i)%finalize()
       call bc_list_add(this%bclst_neumann, this%neumann_bcs(i))
    end do

  end subroutine scalar_scheme_add_bcs

  !> Initialize all related components of the current scheme
  !! @param msh The mesh.
  !! @param c_Xh The coefficients.
  !! @param gs_Xh The gather-scatter.
  !! @param params The case parameter file in json.
  !! @param scheme The name of the scalar scheme.
  !! @param user Type with user-defined procedures.
  subroutine scalar_scheme_init(this, msh, c_Xh, gs_Xh, params, scheme, user, &
                                material_properties)
    class(scalar_scheme_t), target, intent(inout) :: this
    type(mesh_t), target, intent(inout) :: msh
    type(coef_t), target, intent(inout) :: c_Xh
    type(gs_t), target, intent(inout) :: gs_Xh
    type(json_file), target, intent(inout) :: params
    character(len=*), intent(in) :: scheme
    type(user_t), target, intent(in) :: user
    type(material_properties_t), target,  intent(inout) :: material_properties
    ! IO buffer for log output
    character(len=LOG_SIZE) :: log_buf
    ! Variables for retrieving json parameters
    logical :: logical_val
    real(kind=rp) :: real_val, solver_abstol
    integer :: integer_val
    character(len=:), allocatable :: solver_type, solver_precon

    this%u => neko_field_registry%get_field('u')
    this%v => neko_field_registry%get_field('v')
    this%w => neko_field_registry%get_field('w')

    call neko_log%section('Scalar')
    call json_get(params, 'case.fluid.velocity_solver.type', solver_type)
    call json_get(params, 'case.fluid.velocity_solver.preconditioner',&
                  solver_precon)
    call json_get(params, 'case.fluid.velocity_solver.absolute_tolerance',&
                  solver_abstol)

    !
    ! Material properties
    !
    this%rho => material_properties%rho
    this%lambda => material_properties%lambda
    this%cp => material_properties%cp

    write(log_buf, '(A,ES13.6)') 'rho        :',  this%rho
    call neko_log%message(log_buf)
    write(log_buf, '(A,ES13.6)') 'lambda     :',  this%lambda
    call neko_log%message(log_buf)
    write(log_buf, '(A,ES13.6)') 'cp         :',  this%cp
    call neko_log%message(log_buf)

    call json_get_or_default(params, &
                            'case.fluid.velocity_solver.projection_space_size',&
                            this%projection_dim, 20)


    write(log_buf, '(A, A)') 'Type       : ', trim(scheme)
    call neko_log%message(log_buf)
    call neko_log%message('Ksp scalar : ('// trim(solver_type) // &
         ', ' // trim(solver_precon) // ')')
    write(log_buf, '(A,ES13.6)') ' `-abs tol :',  solver_abstol
    call neko_log%message(log_buf)

    this%Xh => this%u%Xh
    this%dm_Xh => this%u%dof
    this%params => params
    this%msh => msh
    if (.not. neko_field_registry%field_exists('s')) then
       call neko_field_registry%add_field(this%dm_Xh, 's')
    end if
    this%s => neko_field_registry%get_field('s')

    call this%slag%init(this%s, 2)

    this%gs_Xh => gs_Xh
    this%c_Xh => c_Xh


    !
    ! Setup scalar boundary conditions
    !
    call bc_list_init(this%bclst_dirichlet)
    call this%user_bc%init(this%dm_Xh)

    ! Read boundary types from the case file
    allocate(this%bc_labels(NEKO_MSH_MAX_ZLBLS))

    ! A filler value
    this%bc_labels = "not"

    if (params%valid_path('case.scalar.boundary_types')) then
       call json_get(params, &
                     'case.scalar.boundary_types', &
                     this%bc_labels)
    end if


    !
    ! Setup right-hand side field.
    !
    allocate(this%f_Xh)
    call this%f_Xh%init(this%dm_Xh, fld_name="scalar_rhs")

    ! Initialize the source term
    call this%source_term%init(params, this%f_Xh, this%c_Xh, user)

    call scalar_scheme_add_bcs(this, msh%labeled_zones, this%bc_labels)


    call this%user_bc%mark_zone(msh%wall)
    call this%user_bc%mark_zone(msh%inlet)
    call this%user_bc%mark_zone(msh%outlet)
    call this%user_bc%mark_zone(msh%outlet_normal)
    call this%user_bc%mark_zone(msh%sympln)
    call this%user_bc%finalize()
    call this%user_bc%set_coef(this%c_Xh)
    if (this%user_bc%msk(0) .gt. 0) call bc_list_add(this%bclst_dirichlet,&
                                                     this%user_bc)


    ! todo parameter file ksp tol should be added
    call json_get_or_default(params, 'case.fluid.velocity_solver.max_iterations',&
                             integer_val, 800)
    call scalar_scheme_solver_factory(this%ksp, this%dm_Xh%size(), &
         solver_type, integer_val, solver_abstol)
    call scalar_scheme_precon_factory(this%pc, this%ksp, &
         this%c_Xh, this%dm_Xh, this%gs_Xh, this%bclst_dirichlet, solver_precon)

    call neko_log%end_section()

  end subroutine scalar_scheme_init


  !> Deallocate a scalar formulation
  subroutine scalar_scheme_free(this)
    class(scalar_scheme_t), intent(inout) :: this

    nullify(this%Xh)
    nullify(this%dm_Xh)
    nullify(this%gs_Xh)
    nullify(this%c_Xh)
    nullify(this%params)

    if (allocated(this%ksp)) then
       call krylov_solver_destroy(this%ksp)
       deallocate(this%ksp)
    end if

    if (allocated(this%pc)) then
       call precon_destroy(this%pc)
       deallocate(this%pc)
    end if

    if (allocated(this%bc_labels)) then
       deallocate(this%bc_labels)
    end if

    call this%source_term%free()

    call bc_list_free(this%bclst_dirichlet)
    call bc_list_free(this%bclst_neumann)

    call this%slag%free()

  end subroutine scalar_scheme_free

  !> Validate that all fields, solvers etc necessary for
  !! performing time-stepping are defined
  subroutine scalar_scheme_validate(this)
    class(scalar_scheme_t), target, intent(inout) :: this

    if ( (.not. allocated(this%u%x)) .or. &
         (.not. allocated(this%v%x)) .or. &
         (.not. allocated(this%w%x)) .or. &
         (.not. allocated(this%s%x))) then
       call neko_error('Fields are not allocated')
    end if

    if (.not. allocated(this%ksp)) then
       call neko_error('No Krylov solver for velocity defined')
    end if

    if (.not. associated(this%Xh)) then
       call neko_error('No function space defined')
    end if

    if (.not. associated(this%dm_Xh)) then
       call neko_error('No dofmap defined')
    end if

    if (.not. associated(this%c_Xh)) then
       call neko_error('No coefficients defined')
    end if

    if (.not. associated(this%f_Xh)) then
       call neko_error('No rhs allocated')
    end if

    if (.not. associated(this%params)) then
       call neko_error('No parameters defined')
    end if

    !
    ! Setup checkpoint structure (if everything is fine)
    !
!    @todo no io for now
!    call this%chkp%init(this%u, this%v, this%w, this%p)

  end subroutine scalar_scheme_validate

  !> Initialize a linear solver
  !! @note Currently only supporting Krylov solvers
  subroutine scalar_scheme_solver_factory(ksp, n, solver, max_iter, abstol)
    class(ksp_t), allocatable, target, intent(inout) :: ksp
    integer, intent(in), value :: n
    integer, intent(in) :: max_iter
    character(len=*), intent(in) :: solver
    real(kind=rp) :: abstol

    call krylov_solver_factory(ksp, n, solver, max_iter, abstol)

  end subroutine scalar_scheme_solver_factory

  !> Initialize a Krylov preconditioner
  subroutine scalar_scheme_precon_factory(pc, ksp, coef, dof, gs, bclst, pctype)
    class(pc_t), allocatable, target, intent(inout) :: pc
    class(ksp_t), target, intent(inout) :: ksp
    type(coef_t), target, intent(inout) :: coef
    type(dofmap_t), target, intent(inout) :: dof
    type(gs_t), target, intent(inout) :: gs
    type(bc_list_t), target, intent(inout) :: bclst
    character(len=*) :: pctype

    call precon_factory(pc, pctype)

    select type(pcp => pc)
    type is(jacobi_t)
       call pcp%init(coef, dof, gs)
    type is (sx_jacobi_t)
       call pcp%init(coef, dof, gs)
    type is (device_jacobi_t)
       call pcp%init(coef, dof, gs)
    type is(hsmg_t)
       if (len_trim(pctype) .gt. 4) then
          if (index(pctype, '+') .eq. 5) then
             call pcp%init(dof%msh, dof%Xh, coef, dof, gs, &
                  bclst, trim(pctype(6:)))
          else
             call neko_error('Unknown coarse grid solver')
          end if
       else
          call pcp%init(dof%msh, dof%Xh, coef, dof, gs, bclst)
       end if
    end select

    call ksp%set_pc(pc)

  end subroutine scalar_scheme_precon_factory

  !> Initialize a user defined scalar bc
  !! @param usr_eval User specified boundary condition for scalar field
  subroutine scalar_scheme_set_user_bc(this, usr_eval)
    class(scalar_scheme_t), intent(inout) :: this
    procedure(usr_scalar_bc_eval) :: usr_eval

    call this%user_bc%set_eval(usr_eval)

  end subroutine scalar_scheme_set_user_bc


end module scalar_scheme
