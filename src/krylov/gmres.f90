!> Defines various GMRES methods
module gmres
  use krylov
  use comm
  use math
  use operators
  use num_types
  implicit none

  !> Standard preconditioned conjugate gradient method
  type, public, extends(ksp_t) :: gmres_t
     integer :: lgmres
     real(kind=rp), allocatable :: w(:)
     real(kind=rp), allocatable :: c(:)
     real(kind=rp), allocatable :: r(:)
     real(kind=rp), allocatable :: z(:,:)
     real(kind=rp), allocatable :: h(:,:)
     real(kind=rp), allocatable :: ml(:)
     real(kind=rp), allocatable :: v(:,:)
     real(kind=rp), allocatable :: s(:)
     real(kind=rp), allocatable :: mu(:)
     real(kind=rp), allocatable :: gam(:)
     real(kind=rp), allocatable :: wk1(:)
     real(kind=rp) :: rnorm
   contains
     procedure, pass(this) :: init => gmres_init
     procedure, pass(this) :: free => gmres_free
     procedure, pass(this) :: solve => gmres_solve
  end type gmres_t

contains

  !> Initialise a standard GMRES solver
  subroutine gmres_init(this, n, M, lgmres, rel_tol, abs_tol)
    class(gmres_t), intent(inout) :: this
    integer, intent(in) :: n
    class(pc_t), optional, intent(inout), target :: M
    integer, optional, intent(inout) :: lgmres
    real(kind=rp), optional, intent(inout) :: rel_tol
    real(kind=rp), optional, intent(inout) :: abs_tol

    if (present(lgmres)) then
       this%lgmres = lgmres
    else
       this%lgmres = 30
    end if
    

    call this%free()
    
    if (present(M)) then 
       this%M => M
    end if

    allocate(this%w(n))
    allocate(this%r(n))
    allocate(this%ml(n))
    allocate(this%mu(n))
    allocate(this%wk1(n))
    
    allocate(this%c(this%lgmres))
    allocate(this%s(this%lgmres))
    allocate(this%gam(this%lgmres + 1))
    
    allocate(this%z(n,this%lgmres))
    allocate(this%v(n,this%lgmres))
    
    allocate(this%h(this%lgmres,this%lgmres))
    
       
    if (present(rel_tol) .and. present(abs_tol)) then
       call this%ksp_init(rel_tol, abs_tol)
    else if (present(rel_tol)) then
       call this%ksp_init(rel_tol=rel_tol)
    else if (present(abs_tol)) then
       call this%ksp_init(abs_tol=abs_tol)
    else
       call this%ksp_init(abs_tol)
    end if
          
  end subroutine gmres_init

  !> Deallocate a standard GMRES solver
  subroutine gmres_free(this)
    class(gmres_t), intent(inout) :: this

    call this%ksp_free()

    if (allocated(this%w)) then
       deallocate(this%w)
    end if

    if (allocated(this%c)) then
       deallocate(this%c)
    end if

    if (allocated(this%r)) then
       deallocate(this%r)
    end if
 
    if (allocated(this%z)) then
       deallocate(this%z)
    end if

    if (allocated(this%h)) then
       deallocate(this%h)
    end if
    
    if (allocated(this%ml)) then
       deallocate(this%ml)
    end if
    
    if (allocated(this%v)) then
       deallocate(this%v)
    end if
    
    if (allocated(this%s)) then
       deallocate(this%s)
    end if
    
    if (allocated(this%mu)) then
       deallocate(this%mu)
    end if
    
    if (allocated(this%gam)) then
       deallocate(this%gam)
    end if
    
    if (allocated(this%wk1)) then
       deallocate(this%wk1)
    end if
    
    nullify(this%M)
    
  end subroutine gmres_free
 
  !> Standard PCG solve
  function gmres_solve(this, Ax, x, f, n, coef, blst, gs_h, niter) result(ksp_results)
    class(gmres_t), intent(inout) :: this
    class(ax_t), intent(inout) :: Ax
    type(field_t), intent(inout) :: x
    integer, intent(inout) :: n
    real(kind=rp), dimension(n), intent(inout) :: f
    type(coef_t), intent(inout) :: coef
    type(bc_list_t), intent(inout) :: blst
    type(gs_t), intent(inout) :: gs_h
    type(ksp_monitor_t) :: ksp_results
    integer, parameter :: BLOCK_SIZE = 1000
    integer, optional, intent(in) :: niter
    integer :: iter, max_iter, glb_n
    integer :: i, j, k, l, ierr 
    real(kind=rp), parameter :: one = 1.0
    real(kind=rp) :: rnorm, w_plus(BLOCK_SIZE), x_plus(BLOCK_SIZE)
    real(kind=rp) ::  alpha, temp, lr, alpha2
    real(kind=rp) :: ratio, div0, norm_fac, tolpss
    logical :: conv
    integer outer

    conv = .false.
    iter = 0
    glb_n = n / x%msh%nelv * x%msh%glb_nelv

    norm_fac = one / sqrt(coef%volume)
    call rone(this%mu, n)
    call rzero(x%x, n)
    call rzero(this%gam, this%lgmres + 1)
    call rone(this%s, this%lgmres)
    call rone(this%c, this%lgmres)
    call rzero(this%h, this%lgmres * this%lgmres)
    outer = 0
    do while (.not. conv .and. iter .lt. niter)
       outer = outer + 1

       if(iter.eq.0) then               
          call copy(this%r,f,n) 
       else
          !update residual
          call copy  (this%r,f,n)      
          call Ax%compute(this%w, x%x, coef, x%msh, x%Xh)
          call gs_op(gs_h, this%w, n, GS_OP_ADD)
          call bc_list_apply(blst, this%w, n)
          call add2s2(this%r,this%w,-one,n) 
       endif
       this%gam(1) = sqrt(glsc3(this%r, this%r, coef%mult, n))
       if(iter.eq.0) then
          div0 = this%gam(1) * norm_fac
          ksp_results%res_start = div0
       endif

       if ( this%gam(1) .eq. 0) return

       rnorm = 0.0_rp
       temp = one / this%gam(1)
       call cmult2(this%v(1,1), this%r, temp, n) 
       do j = 1, this%lgmres
          iter = iter+1
          !Apply precond
          call this%M%solve(this%z(1,j), this%v(1,j), n)

!          call ortho(this%z(1,j),n,glb_n) ! Orthogonalize wrt null space, if present
          call Ax%compute(this%w, this%z(1,j), coef, x%msh, x%Xh)
          call gs_op(gs_h, this%w, n, GS_OP_ADD)
          call bc_list_apply(blst, this%w, n)

          !do l = 1, j
          !   this%h(l,j) = vlsc3(this%w, this%v(1,l), coef%mult, n) 
          !enddo
          do l = 1, j
             this%h(l,j) = 0.0
          enddo

          do i = 1,n,BLOCK_SIZE
              if (i + BLOCK_SIZE .le. n) then
                 do l = 1,j
                    do k = 1, BLOCK_SIZE
                       this%h(l,j) = this%h(l,j) + this%w(i+k)*this%v(i+k,l)*coef%mult(i+k,1,1,1)
                    end do
                 end do
              else 
                 do k = 1, n-i
                    do l = 1, j
                       this%h(l,j) = this%h(l,j) + this%w(i+k)*this%v(i+k,l)*coef%mult(i+k,1,1,1)
                    end do
                 end do
              end if
          end do 
       
          !Could probably be done inplace...
          call MPI_Allreduce(this%h(1,j), this%wk1, j, &
               MPI_REAL_PRECISION, MPI_SUM, NEKO_COMM, ierr)
          call copy(this%h(1,j), this%wk1, j) 

          !do l=1,j
          !   call add2s2(this%w, this%v(1,l), -this%h(l,j), n)
          !enddo                                            
          alpha2 = 0.0_rp
          do i = 1,n,BLOCK_SIZE
              if (i + BLOCK_SIZE .le. n) then
                 do k = 1, BLOCK_SIZE
                    w_plus(k) = 0.0
                 end do
                 do l = 1,j
                    do k = 1, BLOCK_SIZE
                       w_plus(k) = w_plus(k) - this%h(l,j)*this%v(i+k,l)
                    end do
                 end do
                 do k = 1, BLOCK_SIZE
                    this%w(i+k) = this%w(i+k)+w_plus(k)
                    alpha2 = alpha2 + this%w(i+k)**2*coef%mult(i+k,1,1,1)
                 end do
              else 
                 do k = 1, n-i
                    w_plus(1) = 0.0
                    do l = 1, j
                       w_plus(1) = w_plus(1) - this%h(l,j)*this%v(i+k,l)
                    end do
                    this%w(i+k) = this%w(i+k) + w_plus(1)
                    alpha2 = alpha2 + this%w(i+k)**2*coef%mult(i+k,1,1,1)
                 end do
              end if
          end do 
          call MPI_Allreduce(alpha2, alpha, 1, &
               MPI_REAL_PRECISION, MPI_SUM, NEKO_COMM, ierr)
          !apply Givens rotations to new column
          do i=1,j-1
             temp = this%h(i,j)                   
             this%h(i  ,j) =  this%c(i)*temp + this%s(i)*this%h(i+1,j)  
             this%h(i+1,j) = -this%s(i)*temp + this%c(i)*this%h(i+1,j)
          enddo
          alpha = sqrt(alpha)   
          rnorm = 0.0_rp
          if(alpha .eq. 0.0_rp) then 
            conv = .true.
            exit
          end if
          lr = sqrt(this%h(j,j) * this%h(j,j) + alpha**2)
          temp = one / lr
          this%c(j) = this%h(j,j) * temp
          this%s(j) = alpha  * temp
          this%h(j,j) = lr
          this%gam(j+1) = -this%s(j) * this%gam(j)
          this%gam(j)   =  this%c(j) * this%gam(j)

          rnorm = abs(this%gam(j+1)) * norm_fac
          ratio = rnorm / div0
          if (rnorm .lt. this%abs_tol) then 
             conv = .true.
             exit
          end if
         
          if (iter + 1 .gt. niter) exit
          
          if( j .lt. this%lgmres) then
            temp = one / alpha
            call cmult2(this%v(1,j+1), this%w, temp, n)
          endif
       enddo
       j = min(j, this%lgmres)
       !back substitution
       do k = j, 1, -1
          temp = this%gam(k)
          do i = j, k+1, -1
             temp = temp - this%h(k,i) * this%c(i)
          enddo
          this%c(k) = temp / this%h(k,k)
       enddo
       !sum up Arnoldi vectors
       !do l = 1, j
       !   call add2s2(x%x, this%z(1,l), this%c(l), n) ! x = x + c  z
       !enddo                                          !          i  i
       do i = 1,n,BLOCK_SIZE
          if (i + BLOCK_SIZE .le. n) then
             do k = 1, BLOCK_SIZE
                x_plus(k) = 0.0
             end do
             do l = 1,j
                do k = 1, BLOCK_SIZE
                   x_plus(k) = x_plus(k) + this%c(l)*this%z(i+k,l)
                end do
             end do
             do k = 1, BLOCK_SIZE
                x%x(i+k,1,1,1) = x%x(i+k,1,1,1)+x_plus(k)
             end do
          else 
             do k = 1, n-i
                x_plus(1) = 0.0
                do l = 1, j
                   x_plus(1) = x_plus(1) + this%c(l)*this%z(i+k,l)
                end do
                x%x(i+k,1,1,1) = x%x(i+k,1,1,1) + x_plus(1)
             end do
          end if
       end do 
    enddo
!    call ortho   (x%x, n, glb_n)
    ksp_results%res_final = rnorm
    ksp_results%iter = iter
  end function gmres_solve

end module gmres
  

