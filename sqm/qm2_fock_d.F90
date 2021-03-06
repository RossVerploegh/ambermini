! <compile=optimized>
#include "copyright.h"
#include "../include/dprec.fh"
! *********************************************************************         
! The following soubroutines calculate the one electron and two electron
! contribution to the fock matrix (with d-orbital implementation.
! They are NOT optimized yet.
!
!  By Taisung Lee (Rutgers, 2011)                                                                              
!                                                                               
! *********************************************************************

module qm2_fock_d

    public qm2_fock1_d, qm2_fock2_d, W2Fock_atompair
   
    private InitializeWPosition, w_position

    integer, save, allocatable::w_position(:,:)
    logical, save ::w_position_initialized=.false.
    
contains 

  
subroutine qm2_fock2_d(F, PTOT, W)
!***********************************************************************        
!                                                                               
! FOCK2 FORMS THE TWO-ELECTRON TWO-CENTER REPULSION PART OF THE FOCK            
! MATRIX                                                                        
! ON INPUT  PTOT = TOTAL DENSITY MATRIX.                                        
!           W    = TWO-ELECTRON INTEGRAL MATRIX.                                
!                                                                               
!  ON OUTPUT F   = PARTIAL FOCK MATRIX                                          
!***********************************************************************        
    use qmmm_module, only : qmmm_struct, qm2_struct, qm2_params
    use qmmm_module, only : qmmm_struct, qm2_struct, qm2_params
    implicit none

    _REAL_, intent(inout) :: F(:)
    _REAL_, intent(in) :: ptot(:)
    _REAL_, intent(in) :: W(:)

!Local

    integer:: m,i,j, k, l, ii, ia, ib, jk, kj, jj
    integer:: starting, size

    if (.not.w_position_initialized) call InitializeWPosition
 
    do ii=1,qmmm_struct%nquant_nlink
     IA=qm2_params%orb_loc(1,ii)
     IB=qm2_params%orb_loc(2,ii)
     M=0
     do J=IA,IB
        do K=IA,IB
           M=M+1
           JK=MIN(J,K)
           KJ=K+J-JK
           JK=JK+qm2_params%pascal_tri1(KJ)
           qm2_struct%fock2_PTOT2(M,ii)=PTOT(JK)
        end do
     end do
    end do
          
    do ii=1,qmmm_struct%nquant_nlink
        do jj=1, qmmm_struct%nquant_nlink
        
           k=qm2_params%orb_loc(1,ii)
           l=qm2_params%orb_loc(1,jj)
           if (ii.ne.jj) then
            
            i=qm2_params%natomic_orbs(ii)
            j=qm2_params%natomic_orbs(jj)
            starting=w_position(ii,jj)
            size=( i*(i+1)*j*(j+1) ) /4
            
            call W2Fock_atompair(W(starting:starting+size-1), F, ptot, &
                i, j, k, l)
           end if
        end do
    end do   

    return
end subroutine qm2_fock2_d


subroutine qm2_fock1_d(F, PTOT, first)  ! lam81
!subroutine qm2_fock1_d(F, PTOT)        ! lam81

    use constants          , only : fourth
    use ElementOrbitalIndex, only : MaxValenceDimension, &
                                    Index1_2Electron, IntRep,  &
                                    IntRf1, IntRf2, IntIJ, IntKL
    use MNDOChargeSeparation, only: GetOneCenter2Electron
#ifdef MPI
    use qmmm_module         , only : qmmm_mpi, qmmm_struct, qm2_params
#else
    use qmmm_module         , only : qmmm_struct, qm2_params
#endif
    implicit none

    _REAL_, intent(inout) :: F(:)
    _REAL_, intent(in) :: PTOT(:)
    LOGICAL,intent(in) :: first  ! lam81 

 ! local
 
    _REAL_, save::W(Index1_2Electron)=0.0D0
    _REAL_::F_local(MaxValenceDimension), P_local(MaxValenceDimension)
    integer, save::qmType_saved=-1
    logical, save::initialized=.false. 
    
    integer::i,j,k,i1,i2,ij,kl,counter
    integer::qmType
  
#ifdef MPI  
include 'mpif.h'
#endif

    if(first) then                  ! lam81
     initialized=.false.            ! lam81
     w_position_initialized=.false. ! lam81
    end if                          ! lam81
  
    if (.not.w_position_initialized) call InitializeWPosition

    ! first calculate the SP contributions
    call qm2_fock1(F,PTOT)
    
    ! MC/AWG: d orbital part not parallelized
    ! should not be a major bottleneck since only few atoms
    ! will have d orbitals in general
#ifdef MPI
    if (qmmm_mpi%commqmmm_master) then
#endif

      do i=1,qmmm_struct%nquant_nlink
          qmType=qmmm_struct%qm_atom_type(i)
          k=qm2_params%natomic_orbs(i)
          
          if (k.ge.9) then !only do those atoms w/ d-orbitals
          
              ! the integrals
              if ((.not.initialized).or. (qmType.ne.qmType_saved)) then
                  do j=1,Index1_2Electron
                       i1 = IntRf1(j)
                       i2 = IntRf2(j)
                       W(j) = GetOneCenter2Electron(qmType, IntRep(j))
                       if(i1>0) W(j) = W(j)-fourth*GetOneCenter2Electron(qmType,i1)
                       if(i2>0) W(j) = W(j)-fourth*GetOneCenter2Electron(qmType,i2)
                  end do
                  qmType_saved=qmType
                  initialized=.true.
              end if
  
  
              ! Copy the density matrix to local
              
              i1=qm2_params%orb_loc(1,i)
              i2=qm2_params%orb_loc(2,i)
              counter=0
              do j=i1, i2
                  do k=qm2_params%pascal_tri1(j)+i1, qm2_params%pascal_tri2(j)-1
                      counter=counter+1
                      P_local(counter)=PTOT(k)*2.d0  ! off-diag terms need to be
                              ! doubled to account for the half matrix summation
                  end do
                  counter=counter+1
                  P_local(counter)=PTOT(qm2_params%pascal_tri2(j))
              end do
  
              ! the coulombic contribution
              F_local=0.0D0
              do j=1,Index1_2Electron
                ij=IntIJ(j)
                kl=IntKL(j)
                F_local(ij)=F_local(ij)+P_local(kl)*W(j)
              end do
              
              ! the exchange contribution
              ! no exchange for the RHF case
              ! the UHF case--to be done later
  
              ! add local contribution back to the Fock matrix
              i1=qm2_params%orb_loc(1,i)
              i2=qm2_params%orb_loc(2,i)
              counter=0
              do j=i1, i2
                  do k=qm2_params%pascal_tri1(j)+i1, qm2_params%pascal_tri2(j)
                      counter=counter+1
                      F(k)=F(k)+F_local(counter)
                  end do
              end do            
  
          end if
      end do

#ifdef MPI
    end if
#endif
           

    return
end subroutine qm2_fock1_d

subroutine W2Fock_atompair(W, F, D, norbs_a, norbs_b,  &
          na_starting, nb_starting)

  use constants, only : half

    implicit none

    integer, intent(in)::norbs_a, norbs_b
    integer, intent(in)::na_starting
    integer, intent(in)::nb_starting    

    _REAL_, intent(in)::W(*), D(*)
    _REAL_, intent(inout)::F(*)

    !local
    integer, parameter::orbital_length(3)=(/ 1, 4, 9 /)
    integer, parameter::pair_length(3)=(/1, 10, 45 /)
    
    !the w_index needs "lots" of memory but significantly improves
    !the size and readability of the code
    !
    integer, save::w_index(9,9,9,9,3,3)
    logical, save::initialized=.false. 

    integer::i,j,k,l,a1,a2,b1,b2, ii,jj
    integer::na, nb, counter_ij, counter_kl, location
    integer::index_Fa(norbs_a,norbs_a), index_Fb(norbs_b,norbs_b)
    integer::index_Fab(norbs_a,norbs_b)
    
    _REAL_::temp1, tt1(81)
    logical::toCalc(81)
   

    if (.not. initialized) then
    
        w_index=-1  
        do na=1,3
        do nb=1,3        
            counter_ij=0
            do i=1, orbital_length(na) 
                do j=1, i
                    counter_ij=counter_ij+1
                    counter_kl=0
                    do k=1, orbital_length(nb)
                        do l=1, k
                            counter_kl=counter_kl+1
                            location=(counter_ij-1)*pair_length(nb)+counter_kl
                            w_index(i,j,k,l, na, nb)=location
                            w_index(i,j,l,k, na, nb)=location
                            w_index(j,i,k,l, na, nb)=location
                            w_index(j,i,l,k, na, nb)=location                                                         
                        end do !l
                    end do !k
                end do !j
            end do !i  
       
       end do ! nb
       end do ! na                                                                    

       initialized=.true.  
      ! initialized=.false.  ! lam81
    endif 
   
    do i=1, norbs_a
        ii=na_starting+i-1
        jj=ii*(ii-1)/2+na_starting-1
        do j=1, i
            location=jj+j
            index_Fa(i, j)=location
            index_Fa(j, i)=location
        end do !nb       
    end do
    do k=1, norbs_b
        ii=nb_starting+k-1
        jj=ii*(ii-1)/2+nb_starting-1
        do l=1, k
            location=jj+l
            index_Fb(k, l)=location
            index_Fb(l, k)=location
        end do !nb       
    end do
    
    if (na_starting.ge.nb_starting) then
        k=0
        a1=na_starting
        b1=nb_starting
        a2=norbs_a
        b2=norbs_b
    else
        k=1 
        a1=nb_starting
        b1=na_starting
        a2=norbs_b
        b2=norbs_a
    end if         
    do i=1, a2
        ii=a1+i-1
        jj=ii*(ii-1)/2
        do j=1, b2
            location=jj+b1+j-1
            if (k==0) then
                index_Fab(i, j)=location
            else
                index_Fab(j, i)=location
            end if
        end do !nb       
    end do    
 
! real stuff

    na=int(sqrt(dble(norbs_a)+1.0D-5))
    nb=int(sqrt(dble(norbs_b)+1.0D-5))
          
    ! for the coloumbic part, calculate all na/nb pairs but be carful about the index for W
    ii=1
    do k=1, norbs_b
        do l=1, k-1
           tt1(ii)=D(index_Fb(l,k))*2
           ii=ii+1
        end do
        tt1(ii)=D(index_Fb(k,k))
        ii=ii+1
    end do
                 
    do i=1, norbs_a
        do j=1, i
       
            temp1=0.0D0    
            if (na_starting.gt.nb_starting) then  
                ii=1      
                do k=1, norbs_b
                    do l=1, k
                        temp1=temp1+tt1(ii)* & 
                            W(w_index(i,j,k,l,na,nb))
                        ii=ii+1
                    end do
                end do
            else
                ii=1
                do k=1, norbs_b
                    do l=1, k
                        temp1=temp1+tt1(ii)* & 
                            W(w_index(k,l,i,j,nb,na))
                        ii=ii+1
                    end do
                end do
            end if  !na_starting.lt.nb_starting 

            F(index_Fa(i,j))=F(index_Fa(i,j))+temp1
        end do 
    end do


    ! for the exchange part, only calculates when na_starting.gt.nb_starting
    ! to avoid double counting
    if (na_starting.gt.nb_starting) then
        ii=1
        do l=1, norbs_b
            do j=1, norbs_a
               tt1(ii)=D(index_Fab(j,l))
               if (abs(tt1(ii))>1.0d-6) then
                  toCalc(ii)=.true.
               else
                  toCalc(ii)=.false.               
               end if
               ii=ii+1
            end do
        end do
               
        do i=1, norbs_a
            do k=1, norbs_b
                temp1=0.0D0
                ii=1                                    
                do l=1, norbs_b
                    do j=1, norbs_a
                        !if (toCalc(ii)) then
                            temp1=temp1+tt1(ii)* &
                                W(w_index(i,j,k,l,na,nb))
                            ii=ii+1
                        !end if
                    end do
                end do
                F(index_Fab(i,k))=F(index_Fab(i,k))-temp1*half                            

            end do 
        end do  
   end if  

end subroutine W2Fock_atompair

subroutine InitializeWPosition

    use qmmm_module, only : qmmm_struct, qm2_params
    
    integer::i,j,ii,jj,kk,n
    
    if (w_position_initialized) return
    
    n=qmmm_struct%nquant_nlink
    if (allocated(w_position)) deallocate(w_position)  ! lam81
    allocate(w_position(n,n))
        
    kk=1
    w_position=-1
    do ii=1,n
        do jj=1, ii-1
                i=qm2_params%natomic_orbs(ii)
                j=qm2_params%natomic_orbs(jj)
                
                w_position(ii,jj)=kk
                w_position(jj,ii)=kk

                kk=kk+(i*(i+1)/2)*(j*(j+1)/2)
         end do
    end do
    w_position_initialized=.true.
    !w_position_initialized=.false.  ! lam81
    
end subroutine InitializeWPosition


end module qm2_fock_d
