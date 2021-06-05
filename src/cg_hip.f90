!> Defines various Conjugate Gradient methods for accelerators using HIP
module cg_hip
  use krylov
  use math
  use hip_math    
  use num_types
  use, intrinsic :: iso_c_binding
  implicit none

  !> HIP based preconditioned conjugate gradient method
  type, public, extends(ksp_t) :: cg_hip_t
     real(kind=rp), allocatable :: w(:)
     real(kind=rp), allocatable :: r(:)
     real(kind=rp), allocatable :: p(:)
     real(kind=rp), allocatable :: z(:)
     type(c_ptr) :: w_d, r_d, p_d, z_d
   contains
     procedure, pass(this) :: init => cg_hip_init
     procedure, pass(this) :: free => cg_hip_free
     procedure, pass(this) :: solve => cg_hip_solve
  end type cg_hip_t

contains

  !> Initialise a HIP based PCG solver
  subroutine cg_hip_init(this, n, M, rel_tol, abs_tol)
    class(cg_hip_t), intent(inout) :: this
    class(pc_t), optional, intent(inout), target :: M
    integer, intent(in) :: n
    real(kind=rp), optional, intent(inout) :: rel_tol
    real(kind=rp), optional, intent(inout) :: abs_tol
    
    call this%free()
    
    allocate(this%w(n))
    allocate(this%r(n))
    allocate(this%p(n))
    allocate(this%z(n))

    call device_map(this%z, this%z_d, n)
    call device_map(this%p, this%p_d, n)
    call device_map(this%r, this%r_d, n)
    call device_map(this%w, this%w_d, n)
    
    if (present(M)) then 
       this%M => M
    end if

    if (present(rel_tol) .and. present(abs_tol)) then
       call this%ksp_init(rel_tol, abs_tol)
    else if (present(rel_tol)) then
       call this%ksp_init(rel_tol=rel_tol)
    else if (present(abs_tol)) then
       call this%ksp_init(abs_tol=abs_tol)
    else
       call this%ksp_init()
    end if
          
  end subroutine cg_hip_init

  !> Deallocate a HIP based PCG solver
  subroutine cg_hip_free(this)
    class(cg_hip_t), intent(inout) :: this

    call this%ksp_free()

    if (allocated(this%w)) then
       deallocate(this%w)
    end if

    if (allocated(this%r)) then
       deallocate(this%r)
    end if

    if (allocated(this%p)) then
       deallocate(this%p)
    end if
    
    if (allocated(this%z)) then
       deallocate(this%z)
    end if

    nullify(this%M)

    if (c_associated(this%w_d)) then
       call device_free(this%w_d)
    end if

    if (c_associated(this%r_d)) then
       call device_free(this%r_d)
    end if

    if (c_associated(this%p_d)) then
       call device_free(this%p_d)
    end if

    if (c_associated(this%z_d)) then
       call device_free(this%z_d)
    end if

  end subroutine cg_hip_free
  
  !> Standard PCG solve
  function cg_hip_solve(this, Ax, x, f, n, coef, blst, gs_h, niter) result(ksp_results)
    class(cg_hip_t), intent(inout) :: this
    class(ax_t), intent(inout) :: Ax
    type(field_t), intent(inout) :: x
    integer, intent(inout) :: n
    real(kind=rp), dimension(n), intent(inout) :: f
    type(coef_t), intent(inout) :: coef
    type(bc_list_t), intent(inout) :: blst
    type(gs_t), intent(inout) :: gs_h
    type(ksp_monitor_t) :: ksp_results
    integer, optional, intent(in) :: niter
    real(kind=rp), parameter :: one = 1.0
    real(kind=rp), parameter :: zero = 0.0
    integer :: iter, max_iter
    real(kind=rp) :: rnorm, rtr, rtr0, rtz2, rtz1
    real(kind=rp) :: beta, pap, alpha, alphm, eps, norm_fac
    type(c_ptr) :: x_d, f_d
    
    x_d = device_get_ptr(x%x, n)
    f_d = device_get_ptr(f, n)

    if (present(niter)) then
       max_iter = niter
    else
       max_iter = KSP_MAX_ITER
    end if
    norm_fac = one/sqrt(coef%volume)

    rtz1 = one
    call hip_rzero(x%x_d, n)
    call hip_rzero(this%p_d, n)
    call hip_copy(this%r_d, f_d, n)

    rtr = hip_glsc3(this%r_d, coef%mult_d, this%r_d, n)
    rnorm = sqrt(rtr)*norm_fac
    ksp_results%res_start = rnorm
    ksp_results%res_final = rnorm
    ksp_results%iter = 0
    if(rnorm .eq. zero) return
    do iter = 1, max_iter
       call hip_copy(this%z_d, this%r_d, n)
       rtz2 = rtz1
       rtz1 = hip_glsc3(this%r_d, coef%mult_d, this%z_d, n)
       beta = rtz1 / rtz2
       if (iter .eq. 1) beta = zero
       call hip_add2s1(this%p_d, this%z_d, beta, n)

       call Ax%compute(this%w, this%p, coef, x%msh, x%Xh)       
       call gs_op(gs_h, this%w, n, GS_OP_ADD)       
       call bc_list_apply(blst, this%w, n)       

       pap = hip_glsc3(this%w_d, coef%mult_d, this%p_d, n)

       alpha = rtz1 / pap
       alphm = -alpha
       call hip_add2s2(x_d, this%p_d, alpha, n)
       call hip_add2s2(this%r_d, this%w_d, alphm, n)

       rtr = hip_glsc3(this%r_d, coef%mult_d, this%r_d, n)       
       if (iter .eq. 1) rtr0 = rtr
       rnorm = sqrt(rtr)*norm_fac
       if (rnorm .lt. this%abs_tol) then
          exit
       end if
    end do
    ksp_results%res_final = rnorm
    ksp_results%iter = iter

  end function cg_hip_solve

end module cg_hip
  

