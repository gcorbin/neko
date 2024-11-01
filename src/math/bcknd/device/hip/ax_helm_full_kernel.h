#ifndef __MATH_AX_HELM_FULL_KERNEL_H__
#define __MATH_AX_HELM_FULL_KERNEL_H__
/*
 Copyright (c) 2024, The Neko Authors
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.

   * Redistributions in binary form must reproduce the above
     copyright notice, this list of conditions and the following
     disclaimer in the documentation and/or other materials provided
     with the distribution.

   * Neither the name of the authors nor the names of its
     contributors may be used to endorse or promote products derived
     from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
*/

/**
 * Device kernels for Ax helm full
 */

template< typename T, const int LX >
__global__ void __launch_bounds__(LX*LX,3)
  ax_helm_stress_kernel_vector_kstep(T * __restrict__ au,
                              T * __restrict__ av,
                              T * __restrict__ aw,
                              const T * __restrict__ u,
                              const T * __restrict__ v,
                              const T * __restrict__ w,
                              const T * __restrict__ dx,
                              const T * __restrict__ dy,
                              const T * __restrict__ dz,
                              const T * __restrict__ h1,
                              const T * __restrict__ drdx,
                              const T * __restrict__ drdy,
                              const T * __restrict__ drdz,
                              const T * __restrict__ dsdx,
                              const T * __restrict__ dsdy,
                              const T * __restrict__ dsdz,
                              const T * __restrict__ dtdx,
                              const T * __restrict__ dtdy,
                              const T * __restrict__ dtdz,
                              const T * __restrict__ jacinv,
                              const T * __restrict__ weight3) {

  __shared__ T shdx[LX * LX];
  __shared__ T shdy[LX * LX];
  __shared__ T shdz[LX * LX];

  __shared__ T shu[LX * LX];
  __shared__ T shur[LX * LX];
  __shared__ T shus[LX * LX];

  __shared__ T shv[LX * LX];
  __shared__ T shvr[LX * LX];
  __shared__ T shvs[LX * LX];

  __shared__ T shw[LX * LX];
  __shared__ T shwr[LX * LX];
  __shared__ T shws[LX * LX];

  T ru[LX];
  T rv[LX];
  T rw[LX];

  T ruw[LX];
  T rvw[LX];
  T rww[LX];

  T rut;
  T rvt;
  T rwt;

  const int e = blockIdx.x;
  const int j = threadIdx.y;
  const int i = threadIdx.x;
  const int ij = i + j*LX;
  const int ele = e*LX*LX*LX;

  shdx[ij] = dx[ij];
  shdy[ij] = dy[ij];
  shdz[ij] = dz[ij];

#pragma unroll
  for(int k = 0; k < LX; ++k){
    ru[k] = u[ij + k*LX*LX + ele];
    ruw[k] = 0.0;

    rv[k] = v[ij + k*LX*LX + ele];
    rvw[k] = 0.0;

    rw[k] = w[ij + k*LX*LX + ele];
    rww[k] = 0.0;
  }


  __syncthreads();
#pragma unroll
  for (int k = 0; k < LX; ++k){
    const int ijk = ij + k*LX*LX;
    const T J_inv11 = drdx[ijk+ele];
    const T J_inv12 = drdy[ijk+ele];
    const T J_inv13 = drdz[ijk+ele];
    const T J_inv21 = dsdx[ijk+ele];
    const T J_inv22 = dsdy[ijk+ele];
    const T J_inv23 = dsdz[ijk+ele];
    const T J_inv31 = dtdx[ijk+ele];
    const T J_inv32 = dtdy[ijk+ele];
    const T J_inv33 = dtdz[ijk+ele];
    const T dj  = h1[ijk+ele] *
                  weight3[ijk] *
                  jacinv[ijk+ele];

    T uttmp = 0.0;
    T vttmp = 0.0;
    T wttmp = 0.0;
    shu[ij] = ru[k];
    shv[ij] = rv[k];
    shw[ij] = rw[k];
    for (int l = 0; l < LX; l++){
      uttmp += shdz[k+l*LX] * ru[l];
      vttmp += shdz[k+l*LX] * rv[l];
      wttmp += shdz[k+l*LX] * rw[l];
    }
    __syncthreads();

    T urtmp = 0.0;
    T ustmp = 0.0;

    T vrtmp = 0.0;
    T vstmp = 0.0;

    T wrtmp = 0.0;
    T wstmp = 0.0;
#pragma unroll
    for (int l = 0; l < LX; l++){
      urtmp += shdx[i+l*LX] * shu[l+j*LX];
      ustmp += shdy[j+l*LX] * shu[i+l*LX];

      vrtmp += shdx[i+l*LX] * shv[l+j*LX];
      vstmp += shdy[j+l*LX] * shv[i+l*LX];

      wrtmp += shdx[i+l*LX] * shw[l+j*LX];
      wstmp += shdy[j+l*LX] * shw[i+l*LX];
    }

    T u1 = 0.0;
    T u2 = 0.0;
    T u3 = 0.0;
    T v1 = 0.0;
    T v2 = 0.0;
    T v3 = 0.0;
    T w1 = 0.0;
    T w2 = 0.0;
    T w3 = 0.0;

    u1 = urtmp * J_inv11 + 
         ustmp * J_inv21 + 
         uttmp * J_inv31;
    u2 = urtmp * J_inv12 + 
         ustmp * J_inv22 + 
         uttmp * J_inv32;
    u3 = urtmp * J_inv13 + 
         ustmp * J_inv23 + 
         uttmp * J_inv33;

    v1 = vrtmp * J_inv11 + 
         vstmp * J_inv21 + 
         vttmp * J_inv31;
    v2 = vrtmp * J_inv12 + 
         vstmp * J_inv22 + 
         vttmp * J_inv32;
    v3 = vrtmp * J_inv13 + 
         vstmp * J_inv23 + 
         vttmp * J_inv33;

    w1 = wrtmp * J_inv11 + 
         wstmp * J_inv21 + 
         wttmp * J_inv31;
    w2 = wrtmp * J_inv12 + 
         wstmp * J_inv22 + 
         wttmp * J_inv32;
    w3 = wrtmp * J_inv13 + 
         wstmp * J_inv23 + 
         wttmp * J_inv33;
    
    T s11 = 0.0;
    T s12 = 0.0;
    T s13 = 0.0;
    T s21 = 0.0;
    T s22 = 0.0;
    T s23 = 0.0;
    T s31 = 0.0;
    T s32 = 0.0;
    T s33 = 0.0;

    s11 = dj*(u1 + u1);
    s12 = dj*(u2 + v1);
    s13 = dj*(u3 + w1);
    s21 = dj*(v1 + u2);
    s22 = dj*(v2 + v2);
    s23 = dj*(v3 + w2);
    s31 = dj*(w1 + u3);
    s32 = dj*(w2 + v3);
    s33 = dj*(w3 + w3);

    shur[ij] = J_inv11 * s11 +
               J_inv12 * s12 +
               J_inv13 * s13;
    shus[ij] = J_inv21 * s11 +
               J_inv22 * s12 +
               J_inv23 * s13;
    rut =      J_inv31 * s11 +
               J_inv32 * s12 +
               J_inv33 * s13;
    
    shvr[ij] = J_inv11 * s21 +
               J_inv12 * s22 +
               J_inv13 * s23;
    shvs[ij] = J_inv21 * s21 +
               J_inv22 * s22 +
               J_inv23 * s23;
    rvt =      J_inv31 * s21 +
               J_inv32 * s22 +
               J_inv33 * s23;

    shwr[ij] = J_inv11 * s31 +
               J_inv12 * s32 +
               J_inv13 * s33;
    shws[ij] = J_inv21 * s31 +
               J_inv22 * s32 +
               J_inv23 * s33;
    rwt =      J_inv31 * s31 +
               J_inv32 * s32 +
               J_inv33 * s33;

    __syncthreads();

    T uwijke = 0.0;
    T vwijke = 0.0;
    T wwijke = 0.0;
#pragma unroll
    for (int l = 0; l < LX; l++){
      uwijke += shur[l+j*LX] * shdx[l+i*LX];
      ruw[l] += rut * shdz[k+l*LX];
      uwijke += shus[i+l*LX] * shdy[l + j*LX];

      vwijke += shvr[l+j*LX] * shdx[l+i*LX];
      rvw[l] += rvt * shdz[k+l*LX];
      vwijke += shvs[i+l*LX] * shdy[l + j*LX];

      wwijke += shwr[l+j*LX] * shdx[l+i*LX];
      rww[l] += rwt * shdz[k+l*LX];
      wwijke += shws[i+l*LX] * shdy[l + j*LX];
    }
    ruw[k] += uwijke;
    rvw[k] += vwijke;
    rww[k] += wwijke;
  }
#pragma unroll
  for (int k = 0; k < LX; ++k){
   au[ij + k*LX*LX + ele] = ruw[k];
   av[ij + k*LX*LX + ele] = rvw[k];
   aw[ij + k*LX*LX + ele] = rww[k];
  }
}

// template< typename T, const int LX >
// __global__ void __launch_bounds__(LX*LX,3)
//   ax_helm_stress_kernel_vector_kstep_padded(T * __restrict__ au,
//                                      T * __restrict__ av,
//                                      T * __restrict__ aw,
//                                      const T * __restrict__ u,
//                                      const T * __restrict__ v,
//                                      const T * __restrict__ w,
//                                      const T * __restrict__ dx,
//                                      const T * __restrict__ dy,
//                                      const T * __restrict__ dz,
//                                      const T * __restrict__ h1,
//                                      const T * __restrict__ g11,
//                                      const T * __restrict__ g22,
//                                      const T * __restrict__ g33,
//                                      const T * __restrict__ g12,
//                                      const T * __restrict__ g13,
//                                      const T * __restrict__ g23) {

//   __shared__ T shdx[LX * (LX+1)];
//   __shared__ T shdy[LX * (LX+1)];
//   __shared__ T shdz[LX * (LX+1)];

//   __shared__ T shu[LX * (LX+1)];
//   __shared__ T shur[LX * LX];
//   __shared__ T shus[LX * (LX+1)];

//   __shared__ T shv[LX * (LX+1)];
//   __shared__ T shvr[LX * LX];
//   __shared__ T shvs[LX * (LX+1)];

//   __shared__ T shw[LX * (LX+1)];
//   __shared__ T shwr[LX * LX];
//   __shared__ T shws[LX * (LX+1)];

//   T ru[LX];
//   T rv[LX];
//   T rw[LX];

//   T ruw[LX];
//   T rvw[LX];
//   T rww[LX];

//   T rut;
//   T rvt;
//   T rwt;

//   const int e = blockIdx.x;
//   const int j = threadIdx.y;
//   const int i = threadIdx.x;
//   const int ij = i + j*LX;
//   const int ij_p = i + j*(LX+1);
//   const int ele = e*LX*LX*LX;

//   shdx[ij_p] = dx[ij];
//   shdy[ij_p] = dy[ij];
//   shdz[ij_p] = dz[ij];

// #pragma unroll
//   for(int k = 0; k < LX; ++k){
//     ru[k] = u[ij + k*LX*LX + ele];
//     ruw[k] = 0.0;

//     rv[k] = v[ij + k*LX*LX + ele];
//     rvw[k] = 0.0;

//     rw[k] = w[ij + k*LX*LX + ele];
//     rww[k] = 0.0;
//   }


//   __syncthreads();
// #pragma unroll
//   for (int k = 0; k < LX; ++k){
//     const int ijk = ij + k*LX*LX;
//     const T G00 = g11[ijk+ele];
//     const T G11 = g22[ijk+ele];
//     const T G22 = g33[ijk+ele];
//     const T G01 = g12[ijk+ele];
//     const T G02 = g13[ijk+ele];
//     const T G12 = g23[ijk+ele];
//     const T H1  = h1[ijk+ele];
//     T uttmp = 0.0;
//     T vttmp = 0.0;
//     T wttmp = 0.0;
//     shu[ij_p] = ru[k];
//     shv[ij_p] = rv[k];
//     shw[ij_p] = rw[k];
//     for (int l = 0; l < LX; l++){
//       uttmp += shdz[k+l*(LX+1)] * ru[l];
//       vttmp += shdz[k+l*(LX+1)] * rv[l];
//       wttmp += shdz[k+l*(LX+1)] * rw[l];
//     }
//     __syncthreads();

//     T urtmp = 0.0;
//     T ustmp = 0.0;

//     T vrtmp = 0.0;
//     T vstmp = 0.0;

//     T wrtmp = 0.0;
//     T wstmp = 0.0;
// #pragma unroll
//     for (int l = 0; l < LX; l++){
//       urtmp += shdx[i+l*(LX+1)] * shu[l+j*(LX+1)];
//       ustmp += shdy[j+l*(LX+1)] * shu[i+l*(LX+1)];

//       vrtmp += shdx[i+l*(LX+1)] * shv[l+j*(LX+1)];
//       vstmp += shdy[j+l*(LX+1)] * shv[i+l*(LX+1)];

//       wrtmp += shdx[i+l*(LX+1)] * shw[l+j*(LX+1)];
//       wstmp += shdy[j+l*(LX+1)] * shw[i+l*(LX+1)];
//     }

//     shur[ij] = H1
//              * (G00 * urtmp
//                 + G01 * ustmp
//                 + G02 * uttmp);
//     shus[ij_p] = H1
//                * (G01 * urtmp
//                   + G11 * ustmp
//                   + G12 * uttmp);
//     rut      = H1
//              * (G02 * urtmp
//                 + G12 * ustmp
//                 + G22 * uttmp);

//     shvr[ij] = H1
//              * (G00 * vrtmp
//                 + G01 * vstmp
//                 + G02 * vttmp);
//     shvs[ij_p] = H1
//                * (G01 * vrtmp
//                   + G11 * vstmp
//                   + G12 * vttmp);
//     rvt      = H1
//              * (G02 * vrtmp
//                 + G12 * vstmp
//                 + G22 * vttmp);

//     shwr[ij] = H1
//              * (G00 * wrtmp
//                 + G01 * wstmp
//                 + G02 * wttmp);
//     shws[ij_p] = H1
//                * (G01 * wrtmp
//                   + G11 * wstmp
//                   + G12 * wttmp);
//     rwt      = H1
//              * (G02 * wrtmp
//                 + G12 * wstmp
//                 + G22 * wttmp);

//     __syncthreads();

//     T uwijke = 0.0;
//     T vwijke = 0.0;
//     T wwijke = 0.0;
// #pragma unroll
//     for (int l = 0; l < LX; l++){
//       uwijke += shur[l+j*LX] * shdx[l+i*(LX+1)];
//       ruw[l] += rut * shdz[k+l*(LX+1)];
//       uwijke += shus[i+l*(LX+1)] * shdy[l + j*(LX+1)];

//       vwijke += shvr[l+j*LX] * shdx[l+i*(LX+1)];
//       rvw[l] += rvt * shdz[k+l*(LX+1)];
//       vwijke += shvs[i+l*(LX+1)] * shdy[l + j*(LX+1)];

//       wwijke += shwr[l+j*LX] * shdx[l+i*(LX+1)];
//       rww[l] += rwt * shdz[k+l*(LX+1)];
//       wwijke += shws[i+l*(LX+1)] * shdy[l + j*(LX+1)];
//     }
//     ruw[k] += uwijke;
//     rvw[k] += vwijke;
//     rww[k] += wwijke;
//   }
// #pragma unroll
//   for (int k = 0; k < LX; ++k){
//    au[ij + k*LX*LX + ele] = ruw[k];
//    av[ij + k*LX*LX + ele] = rvw[k];
//    aw[ij + k*LX*LX + ele] = rww[k];
//   }
// }

template< typename T >
__global__ void ax_helm_stress_kernel_vector_part2(T * __restrict__ au,
                                            T * __restrict__ av,
                                            T * __restrict__ aw,
                                            const T * __restrict__ u,
                                            const T * __restrict__ v,
                                            const T * __restrict__ w,
                                            const T * __restrict__ h2,
                                            const T * __restrict__ B,
                                            const int n) {
  
  const int idx = blockIdx.x * blockDim.x + threadIdx.x;
  const int str = blockDim.x * gridDim.x;
  
  for (int i = idx; i < n; i += str) {
    au[i] = au[i] + h2[i] * B[i] * u[i];
    av[i] = av[i] + h2[i] * B[i] * v[i];
    aw[i] = aw[i] + h2[i] * B[i] * w[i];
  }
  
}
#endif // __MATH_AX_HELM_FULL_KERNEL_H__
