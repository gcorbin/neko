! Copyright (c) 2020-2021, The Neko Authors
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
!> Dirichlet condition on axis aligned plane in the non normal direction
module non_normal
  use symmetry
  use neko_config
  use num_types
  use dirichlet
  use device
  use coefs
  use math
  use utils
  use stack
  use, intrinsic :: iso_c_binding
  implicit none
  private

  !> Dirichlet condition in non normal direction of a plane
  type, public, extends(symmetry_t) :: non_normal_t
   contains
     procedure, pass(this) :: init_msk => non_normal_init_msk
     final :: non_normal_free
  end type non_normal_t

contains

  !> Initialize symmetry mask for each axis
  subroutine non_normal_init_msk(this, c)
    class(non_normal_t), intent(inout) :: this
    type(coef_t), intent(in) :: c
    type(stack_i4_t) :: xmsk, ymsk, zmsk
    integer :: i, m, j, k, l, idx(4), facet, ntype, msk_size
    integer, pointer :: sp(:)        
    real(kind=rp) :: sx,sy,sz
    real(kind=rp), parameter :: TOL = 1d-3
    
    call non_normal_free(this)

    call xmsk%init()
    call ymsk%init()
    call zmsk%init()
    
    associate(nx => c%nx, ny => c%ny, nz => c%nz)
      m = this%msk(0)
      do i = 1, m
         k = this%msk(i)
         facet = this%facet(i)
         idx = nonlinear_index(k, c%Xh%lx, c%Xh%lx, c%Xh%lx)
         sx = 0d0
         sy = 0d0
         sz = 0d0
         select case (facet)               
         case(1,2)
            do l = 2, c%Xh%lx - 1
               do j = 2, c%Xh%lx -1
                  sx = sx + abs(abs(nx(l, j, facet, idx(4))) - 1d0)
                  sy = sy + abs(abs(ny(l, j, facet, idx(4))) - 1d0)
                  sz = sz + abs(abs(nz(l, j, facet, idx(4))) - 1d0)
               end do
            end do
         case(3,4)
            do l = 2, c%Xh%lx - 1
               do j = 2, c%Xh%lx - 1
                  sx = sx + abs(abs(nx(l, j, facet, idx(4))) - 1d0)
                  sy = sy + abs(abs(ny(l, j, facet, idx(4))) - 1d0)
                  sz = sz + abs(abs(nz(l, j, facet, idx(4))) - 1d0)
               end do
            end do
         case(5,6)
            do l = 2, c%Xh%lx - 1
               do j = 2, c%Xh%lx - 1
                  sx = sx + abs(abs(nx(l, j, facet, idx(4))) - 1d0)
                  sy = sy + abs(abs(ny(l, j, facet, idx(4))) - 1d0)
                  sz = sz + abs(abs(nz(l, j, facet, idx(4))) - 1d0)
               end do
            end do               
         end select
         sx = sx / (c%Xh%lx - 2)**2
         sy = sy / (c%Xh%lx - 2)**2
         sz = sz / (c%Xh%lx - 2)**2

         ntype = 0
         if (sx .lt. TOL) then
            ntype = iand(ntype, 1)
            call ymsk%push(k)
            call zmsk%push(k)
         end if

         if (sy .lt. TOL) then
            ntype = iand(ntype, 2)
            call xmsk%push(k)
            call zmsk%push(k)
         end if

         if (sz .lt. TOL) then
            ntype = iand(ntype, 4)
            call xmsk%push(k)
            call ymsk%push(k)
         end if

      end do
    end associate

    !> @note This is to prevent runtime issues with Cray ftn, gfortran and
    !! msk:size() in the allocate call
    msk_size = xmsk%size()
    if (msk_size .gt. 0) then
       allocate(this%xaxis_msk(0:msk_size))
       this%xaxis_msk(0) = msk_size
       sp => xmsk%array()
       do i = 1, msk_size
          this%xaxis_msk(i) = sp(i)
       end do
       if ((NEKO_BCKND_HIP .eq. 1) .or. (NEKO_BCKND_CUDA .eq. 1) .or. &
            (NEKO_BCKND_OPENCL .eq. 1)) then
          call device_map(this%xaxis_msk, this%xaxis_msk_d, msk_size + 1)
          call device_memcpy(this%xaxis_msk, this%xaxis_msk_d, &
               msk_size + 1, HOST_TO_DEVICE)
       end if
    else
       allocate(this%xaxis_msk(0:1))
       this%xaxis_msk(0) = 0
       if ((NEKO_BCKND_HIP .eq. 1) .or. (NEKO_BCKND_CUDA .eq. 1) .or. &
            (NEKO_BCKND_OPENCL .eq. 1)) then
          call device_map(this%xaxis_msk, this%xaxis_msk_d, 2)
          call device_memcpy(this%xaxis_msk, this%xaxis_msk_d, &
               2, HOST_TO_DEVICE)
       end if
    end if

    msk_size = ymsk%size()
    if (msk_size .gt. 0) then
       allocate(this%yaxis_msk(0:msk_size))
       this%yaxis_msk(0) = msk_size
       sp => ymsk%array()
       do i = 1, msk_size
          this%yaxis_msk(i) = sp(i)
       end do
       if ((NEKO_BCKND_HIP .eq. 1) .or. (NEKO_BCKND_CUDA .eq. 1) .or. &
            (NEKO_BCKND_OPENCL .eq. 1)) then
          call device_map(this%yaxis_msk, this%yaxis_msk_d, msk_size + 1)
          call device_memcpy(this%yaxis_msk, this%yaxis_msk_d, &
               msk_size + 1, HOST_TO_DEVICE)
       end if
    else
       allocate(this%yaxis_msk(0:1))
       this%yaxis_msk(0) = 0
       if ((NEKO_BCKND_HIP .eq. 1) .or. (NEKO_BCKND_CUDA .eq. 1) .or. &
            (NEKO_BCKND_OPENCL .eq. 1)) then
          call device_map(this%yaxis_msk, this%yaxis_msk_d, 2)
          call device_memcpy(this%yaxis_msk, this%yaxis_msk_d, &
               2, HOST_TO_DEVICE)
       end if
    end if

    msk_size = zmsk%size()
    if (msk_size .gt. 0) then
       allocate(this%zaxis_msk(0:msk_size))
       this%zaxis_msk(0) = msk_size
       sp => zmsk%array()
       do i = 1, msk_size
          this%zaxis_msk(i) = sp(i)
       end do
       if ((NEKO_BCKND_HIP .eq. 1) .or. (NEKO_BCKND_CUDA .eq. 1) .or. &
            (NEKO_BCKND_OPENCL .eq. 1)) then
          call device_map(this%zaxis_msk, this%zaxis_msk_d, msk_size + 1)
          call device_memcpy(this%zaxis_msk, this%zaxis_msk_d, &
               msk_size + 1, HOST_TO_DEVICE)
       end if
    else
       allocate(this%zaxis_msk(0:1))
       this%zaxis_msk(0) = 0
       if ((NEKO_BCKND_HIP .eq. 1) .or. (NEKO_BCKND_CUDA .eq. 1) .or. &
            (NEKO_BCKND_OPENCL .eq. 1)) then
          call device_map(this%zaxis_msk, this%zaxis_msk_d, 2)
          call device_memcpy(this%zaxis_msk, this%zaxis_msk_d, &
               2, HOST_TO_DEVICE)
       end if
    end if    

    call xmsk%free()
    call ymsk%free()
    call zmsk%free()
    
  end subroutine non_normal_init_msk

 
  subroutine non_normal_free(this)
    type(non_normal_t), intent(inout) :: this

    if (allocated(this%xaxis_msk)) then
       deallocate(this%xaxis_msk)
    end if
    
    if (allocated(this%yaxis_msk)) then
       deallocate(this%yaxis_msk)
    end if

    if (allocated(this%zaxis_msk)) then
       deallocate(this%zaxis_msk)
    end if

    if (c_associated(this%xaxis_msk_d)) then
       call device_free(this%xaxis_msk_d)
       this%xaxis_msk_d = C_NULL_PTR
    end if

    if (c_associated(this%yaxis_msk_d)) then
       call device_free(this%yaxis_msk_d)
       this%yaxis_msk_d = C_NULL_PTR
    end if

    if (c_associated(this%zaxis_msk_d)) then
       call device_free(this%zaxis_msk_d)
       this%zaxis_msk_d = C_NULL_PTR
    end if

  end subroutine non_normal_free
 end module non_normal