!< Define [[integrand_ladvection]], the 1D linear advection PDE test field that is a concrete extension of the
!< abstract integrand type.

module foodie_test_integrand_ladvection
!< Define [[integrand_ladvection]], the 1D linear advection PDE test field that is a concrete extension of the
!< abstract integrand type.

use, intrinsic :: iso_fortran_env, only : stderr=>error_unit
use flap, only : command_line_interface
use foodie, only : integrand_object
use foodie_test_integrand_tester_object, only : integrand_tester_object
use penf, only : FR_P, I_P, R_P, str, strz
use wenoof, only : interpolator_object, wenoof_create

implicit none
private
public :: integrand_ladvection

type, extends(integrand_tester_object) :: integrand_ladvection
   !< 1D linear advection field.
   !<
   !< It is a FOODIE integrand class concrete extension.
   !<
   !<### 1D linear advection field
   !< The 1D linear advection equation is a conservation law that reads as
   !<$$
   !<\begin{matrix}
   !<u_t = R(u)  \Leftrightarrow u_t = F(u)_x \\
   !<F(u) = a * u
   !<$$
   !< where `a` is scalar constant coefficient. The PDE must completed with the proper initial and boundary conditions.
   !<
   !<#### Numerical grid organization
   !< The finite volume, Godunov's like approach is employed. The conservative variables (and the primitive ones) are co-located at
   !< the cell center. The cell and (inter)faces numeration is as follow.
   !<```
   !<                cell            (inter)faces
   !<                 |                   |
   !<                 v                   v
   !<     |-------|-------|-.....-|-------|-------|-------|-------|-.....-|-------|-------|-------|-.....-|-------|-------|
   !<     | 1-Ng  | 2-Ng  | ..... |  -1   |   0   |   1   |  2    | ..... |  Ni   | Ni+1  | Ni+2  | ..... |Ni+Ng-1| Ni+Ng |
   !<     |-------|-------|-.....-|-------|-------|-------|-------|-.....-|-------|-------|-------|-.....-|-------|-------|
   !<    0-Ng                             -1      0       1       2      Ni-1     Ni                                    Ni+Ng
   !<```
   !< Where *Ni* are the finite volumes (cells) used for discretizing the domain and *Ng* are the ghost cells used for imposing the
   !< left and right boundary conditions (for a total of *2Ng* cells).
   character(99)                           :: w_scheme=''     !< WENO Scheme used.
   integer(I_P)                            :: weno_order=0    !< WENO reconstruction order.
   real(R_P)                               :: weno_eps=0._R_P !< WENO epsilon to avoid division by zero, default value.
   real(R_P)                               :: CFL=0._R_P      !< CFL value.
   integer(I_P)                            :: Ni=0            !< Space dimension.
   integer(I_P)                            :: Ng=0            !< Ghost cells number.
   real(R_P)                               :: length=0._R_P   !< Domain length.
   real(R_P)                               :: Dx=0._R_P       !< Space step.
   real(R_P)                               :: a=0._R_P        !< Advection coefficient.
   real(R_P), allocatable                  :: u(:)            !< Integrand (state) variable.
   class(interpolator_object), allocatable :: interpolator    !< WENO interpolator.
   character(99)                           :: initial_state   !< Initial state.
   contains
      ! auxiliary methods
      procedure, pass(self), public :: destroy          !< Destroy field.
      procedure, pass(self), public :: dt => compute_dt !< Compute the current time step by means of CFL condition.
      procedure, pass(self), public ::       compute_dx !< Compute the space step by means of CFL condition.
      procedure, pass(self), public :: output           !< Extract integrand state field.
      ! integrand_tester_object deferred methods
      procedure, pass(self), public :: description    !< Return an informative description of the test.
      procedure, pass(self), public :: error          !< Return error.
      procedure, pass(self), public :: exact_solution !< Return exact solution.
      procedure, pass(self), public :: export_tecplot !< Export integrand to Tecplot file.
      procedure, pass(self), public :: initialize     !< Initialize integrand.
      procedure, pass(self), public :: parse_cli      !< Initialize from command line interface.
      procedure, nopass,     public :: set_cli        !< Set command line interface.
      ! integrand_object deferred methods
      procedure, pass(self), public :: integrand_dimension !< Return integrand dimension.
      procedure, pass(self), public :: t => dU_dt          !< Time derivative, residuals.
      ! operators
      procedure, pass(lhs), public :: local_error !<`||integrand_ladvection - integrand_ladvection||` operator.
      ! +
      procedure, pass(lhs), public :: integrand_add_integrand !< `+` operator.
      procedure, pass(lhs), public :: integrand_add_real      !< `+ real` operator.
      procedure, pass(rhs), public :: real_add_integrand      !< `real +` operator.
      ! *
      procedure, pass(lhs), public :: integrand_multiply_integrand   !< `*` operator.
      procedure, pass(lhs), public :: integrand_multiply_real        !< `* real` operator.
      procedure, pass(rhs), public :: real_multiply_integrand        !< `real *` operator.
      procedure, pass(lhs), public :: integrand_multiply_real_scalar !< `* real_scalar` operator.
      procedure, pass(rhs), public :: real_scalar_multiply_integrand !< `real_scalar *` operator.
      ! -
      procedure, pass(lhs), public :: integrand_sub_integrand !< `-` operator.
      procedure, pass(lhs), public :: integrand_sub_real      !< `- real` operator.
      procedure, pass(rhs), public :: real_sub_integrand      !< `real -` operator.
      ! =
      procedure, pass(lhs), public :: assign_integrand !< `=` operator.
      procedure, pass(lhs), public :: assign_real      !< `= real` operator.
      ! override fast operators
      ! procedure, pass(self), public :: t_fast                              !< Time derivative, residuals, fast mode.
      ! procedure, pass(opr),  public :: integrand_add_integrand_fast        !< `+` fast operator.
      ! procedure, pass(opr),  public :: integrand_multiply_integrand_fast   !< `*` fast operator.
      ! procedure, pass(opr),  public :: integrand_multiply_real_scalar_fast !< `* real_scalar` fast operator.
      ! procedure, pass(opr),  public :: integrand_subtract_integrand_fast   !< `-` fast operator.
      ! private methods
      procedure, pass(self), private :: impose_boundary_conditions    !< Impose boundary conditions.
      procedure, pass(self), private :: reconstruct_interfaces        !< Reconstruct interface states.
      procedure, pass(self), private :: set_sin_wave_initial_state    !< Set initial state as a sin wave.
      procedure, pass(self), private :: set_square_wave_initial_state !< Set initial state as a square wave.
endtype integrand_ladvection

contains
   ! auxiliary methods
   subroutine destroy(self)
   !< Destroy field.
   class(integrand_ladvection), intent(inout) :: self  !< Advection field.
   type(integrand_ladvection)                 :: fresh !< Fresh field to reset self.

   self = fresh
   endsubroutine destroy

   pure function compute_dt(self, final_time, t) result(Dt)
   !< Compute the current time step by means of CFL condition.
   class(integrand_ladvection), intent(in)           :: self       !< Advection field.
   real(R_P),                   intent(in)           :: final_time !< Maximum integration time.
   real(R_P),                   intent(in), optional :: t          !< Time.
   real(R_P)                                         :: Dt         !< Time step.

   associate(a=>self%a, Dx=>self%Dx, CFL=>self%CFL)
      Dt = Dx * CFL / abs(a)
      if (present(t)) then
         if ((t + Dt) > final_time) Dt = final_time - t
      endif
   endassociate
   endfunction compute_dt

   pure function compute_dx(self, Dt) result(Dx)
   !< Compute the space step step by means of CFL condition.
   class(integrand_ladvection), intent(in) :: self       !< Advection field.
   real(R_P),                   intent(in) :: Dt         !< Time step.
   real(R_P)                               :: Dx         !< Space step.

   associate(a=>self%a, CFL=>self%CFL)
      Dx = Dt / CFL * abs(a)
   endassociate
   endfunction compute_dx

   pure function output(self) result(state)
   !< Output the advection field state.
   class(integrand_ladvection), intent(in) :: self     !< Advection field.
   real(R_P), allocatable                  :: state(:) !< Advection state

   state = self%u(1:self%Ni)
   endfunction output

   ! integrand_tester_object deferred methods
   pure function description(self, prefix) result(desc)
   !< Return informative integrator description.
   class(integrand_ladvection), intent(in)           :: self    !< Integrand.
   character(*),                intent(in), optional :: prefix  !< Prefixing string.
   character(len=:), allocatable                     :: desc    !< Description.
   character(len=:), allocatable                     :: prefix_ !< Prefixing string, local variable.

   prefix_ = '' ; if (present(prefix)) prefix_ = prefix
   desc = prefix//'linear_advection-'//trim(self%initial_state)//'-Ni_'//trim(strz(self%Ni, 10))
   endfunction description

   pure function error(self, t, t0, U0)
   !< Return error.
   class(integrand_ladvection), intent(in)           :: self     !< Integrand.
   real(R_P),                   intent(in)           :: t        !< Time.
   real(R_P),                   intent(in), optional :: t0       !< Initial time.
   class(integrand_object),     intent(in), optional :: U0       !< Initial conditions.
   real(R_P), allocatable                            :: error(:) !< Error.
   integer(I_P)                                      :: i        !< Counter.

   allocate(error(1:1))
   error = 0._R_P
   if (present(U0)) then
      select type(U0)
      type is(integrand_ladvection)
         do i=1, self%Ni
            error = error + (U0%u(i) - self%u(i)) ** 2
         enddo
      endselect
      error = self%Dx * sqrt(error)
   endif
   endfunction error

   pure function exact_solution(self, t, t0, U0) result(exact)
   !< Return exact solution.
   class(integrand_ladvection), intent(in)           :: self     !< Integrand.
   real(R_P),                   intent(in)           :: t        !< Time.
   real(R_P),                   intent(in), optional :: t0       !< Initial time.
   class(integrand_object),     intent(in), optional :: U0       !< Initial conditions.
   real(R_P), allocatable                            :: exact(:) !< Exact solution.
   integer(I_P)                                      :: offset   !< Cells offset.
   integer(I_P)                                      :: i        !< Counter.

   allocate(exact(1:self%Ni))
   if (present(U0)) then
      select type(U0)
      type is(integrand_ladvection)
         offset = nint(mod(self%a * t, self%length) / self%Dx)
         do i=1, self%Ni - offset
            exact(i + offset) = U0%u(i)
         enddo
         do i=self%Ni - offset + 1, self%Ni
            exact(i - self%Ni + offset) = U0%u(i)
         enddo
      endselect
   else
      exact = self%u(1:self%Ni) * 0._R_P
   endif
   endfunction exact_solution

   subroutine export_tecplot(self, file_name, t, scheme, close_file, with_exact_solution, U0)
   !< Export integrand to Tecplot file.
   class(integrand_ladvection), intent(in)           :: self                 !< Advection field.
   character(*),                intent(in), optional :: file_name            !< File name.
   real(R_P),                   intent(in), optional :: t                    !< Time.
   character(*),                intent(in), optional :: scheme               !< Scheme used to integrate integrand.
   logical,                     intent(in), optional :: close_file           !< Flag for closing file.
   logical,                     intent(in), optional :: with_exact_solution  !< Flag for export also exact solution.
   class(integrand_object),     intent(in), optional :: U0                   !< Initial conditions.
   logical                                           :: with_exact_solution_ !< Flag for export also exact solution, local variable.
   logical, save                                     :: is_open=.false.      !< Flag for checking if file is open.
   integer(I_P), save                                :: file_unit            !< File unit.
   real(R_P), allocatable                            :: exact_solution(:)    !< Exact solution.
   integer(I_P)                                      :: i                    !< Counter.

   if (present(close_file)) then
      if (close_file .and. is_open) then
         close(unit=file_unit)
         is_open = .false.
      endif
   else
      with_exact_solution_ = .false. ; if (present(with_exact_solution)) with_exact_solution_ = with_exact_solution
      if (present(file_name)) then
         if (is_open) close(unit=file_unit)
         open(newunit=file_unit, file=trim(adjustl(file_name)))
         is_open = .true.
         write(unit=file_unit, fmt='(A)') 'VARIABLES="x" "u"'
      endif
      if (present(t) .and. present(scheme) .and. is_open) then
         write(unit=file_unit, fmt='(A)') 'ZONE T="'//str(t)//' '//trim(adjustl(scheme))//'"'
         do i=1, self%Ni
            write(unit=file_unit, fmt='(2('//FR_P//',1X))') self%Dx * i - 0.5_R_P * self%Dx, self%u(i)
         enddo
         if (with_exact_solution_) then
            exact_solution = self%exact_solution(t=t, U0=U0)
            write(unit=file_unit, fmt='(A)') 'ZONE T="'//str(t)//' exact solution"'
            do i=1, self%Ni
               write(unit=file_unit, fmt='(2('//FR_P//',1X))') self%Dx * i - 0.5_R_P * self%Dx, exact_solution(i)
            enddo
         endif
      endif
   endif
   endsubroutine export_tecplot

   subroutine initialize(self, Dt)
   !< Initialize integrand.
   class(integrand_ladvection), intent(inout) :: self !< Integrand.
   real(R_P),                   intent(in)    :: Dt   !< Time step.

   self%Dx = self%compute_dx(Dt=Dt)
   self%Ni = nint(self%length / self%Dx)

   select case(trim(adjustl(self%initial_state)))
   case('sin_wave')
      call self%set_sin_wave_initial_state
   case('square_wave')
      call self%set_square_wave_initial_state
   endselect
   endsubroutine initialize

   subroutine parse_cli(self, cli)
   !< Initialize from command line interface.
   class(integrand_ladvection),  intent(inout) :: self !< Advection field.
   type(command_line_interface), intent(inout) :: cli  !< Command line interface handler.

   call self%destroy

   call cli%get(group='linear_advection', switch='--cfl', val=self%CFL, error=cli%error) ; if (cli%error/=0) stop
   call cli%get(group='linear_advection', switch='--w-scheme', val=self%w_scheme, error=cli%error) ; if (cli%error/=0) stop
   call cli%get(group='linear_advection', switch='--weno-order', val=self%weno_order, error=cli%error) ; if (cli%error/=0) stop
   call cli%get(group='linear_advection', switch='--weno-eps', val=self%weno_eps, error=cli%error) ; if (cli%error/=0) stop
   call cli%get(group='linear_advection', switch='-a', val=self%a, error=cli%error) ; if (cli%error/=0) stop
   call cli%get(group='linear_advection', switch='--length', val=self%length, error=cli%error) ; if (cli%error/=0) stop
   call cli%get(group='linear_advection', switch='--Ni', val=self%Ni, error=cli%error) ; if (cli%error/=0) stop
   call cli%get(group='linear_advection', switch='-is', val=self%initial_state, error=cli%error) ; if (cli%error/=0) stop

   self%Ng = (self%weno_order + 1) / 2
   self%Dx = self%length / self%Ni

   if (self%weno_order>1) call wenoof_create(interpolator_type=trim(adjustl(self%w_scheme)), &
                                             S=self%Ng,                                      &
                                             interpolator=self%interpolator,                 &
                                             eps=self%weno_eps)
   endsubroutine parse_cli

   subroutine set_cli(cli)
   !< Set command line interface.
   type(command_line_interface), intent(inout) :: cli !< Command line interface handler.

   call cli%add_group(description='linear advection test settings', group='linear_advection')
   call cli%add(group='linear_advection', switch='--w-scheme', help='WENO scheme', required=.false., act='store', &
                def='reconstructor-JS', choices='reconstructor-JS,reconstructor-M-JS,reconstructor-M-Z,reconstructor-Z')
   call cli%add(group='linear_advection', switch='--weno-order', help='WENO order', required=.false., act='store', def='1')
   call cli%add(group='linear_advection', switch='--weno-eps', help='WENO epsilon parameter', required=.false., act='store', &
                def='0.000001')
   call cli%add(group='linear_advection', switch='--cfl', help='CFL value', required=.false., act='store', def='0.8')
   call cli%add(group='linear_advection', switch='-a', help='advection coefficient', required=.false., act='store', def='1.0')
   call cli%add(group='linear_advection', switch='--length', help='domain lenth', required=.false., act='store', def='1.0')
   call cli%add(group='linear_advection', switch='--Ni', help='number finite volumes used', required=.false., act='store', &
                def='100')
   call cli%add(group='linear_advection', switch='--initial_state', switch_ab='-is', help='initial state', required=.false., &
                act='store', def='sin_wave', choices='sin_wave,square_wave')
   endsubroutine set_cli

   ! integrand_object deferred methods
   function dU_dt(self, t) result(dState_dt)
   !< Time derivative of advection field, the residuals function.
   class(integrand_ladvection), intent(in)           :: self                         !< Advection field.
   real(R_P),                   intent(in), optional :: t                            !< Time.
   real(R_P), allocatable                            :: dState_dt(:)                 !< Advection field time derivative.
   real(R_P)                                         :: u(1-self%Ng:self%Ni+self%Ng) !< Conservative variable.
   real(R_P)                                         :: ur(1:2,0:self%Ni+1)          !< Reconstructed conservative variable.
   real(R_P)                                         :: f(0:self%Ni)                 !< Flux of conservative variable.
   integer(I_P)                                      :: i                            !< Counter.

   do i=1, self%Ni
      u(i) = self%u(i)
   enddo
   call self%impose_boundary_conditions(u=u)
   call self%reconstruct_interfaces(conservative=u, r_conservative=ur)
   do i=0, self%Ni
      call solve_riemann_problem(state_left=ur(2, i), state_right=ur(1, i+1), flux=f(i))
   enddo
   allocate(dState_dt(1:self%Ni))
   do i=1, self%Ni
       dState_dt(i) = (f(i - 1) - f(i)) / self%Dx
   enddo
   contains
      subroutine solve_riemann_problem(state_left, state_right, flux)
      !< Solver Riemann problem of linear advection by upwinding.
      real(R_P), intent(in)  :: state_left  !< Left state.
      real(R_P), intent(in)  :: state_right !< right state.
      real(R_P), intent(out) :: flux        !< Flux of conservative variable.

      if (self%a > 0._R_P) then
         flux = self%a * state_left
      else
         flux = self%a * state_right
      endif
      endsubroutine solve_riemann_problem
   endfunction dU_dt

   pure function integrand_dimension(self)
   !< return integrand dimension.
   class(integrand_ladvection), intent(in) :: self                !< integrand.
   integer(I_P)                            :: integrand_dimension !< integrand dimension.

   integrand_dimension = self%Ni
   endfunction integrand_dimension

   function local_error(lhs, rhs) result(error)
   !< Estimate local truncation error between 2 advection approximations.
   !<
   !< The estimation is done by norm L2 of U:
   !<
   !< $$ error = \sqrt{ \sum_i{\sum_i{ \frac{(lhs\%u_i - rhs\%u_i)^2}{lhs\%u_i^2} }} } $$
   class(integrand_ladvection), intent(in) :: lhs   !< Left hand side.
   class(integrand_object),     intent(in) :: rhs   !< Right hand side.
   real(R_P)                               :: error !< Error estimation.
   integer(I_P)                            :: i     !< Space counter.

   select type(rhs)
   class is (integrand_ladvection)
      error = 0._R_P
      do i=1, lhs%Ni
         error = error + (lhs%u(i) - rhs%u(i)) ** 2
      enddo
      error = sqrt(error)
   endselect
   endfunction local_error

   ! +
   pure function integrand_add_integrand(lhs, rhs) result(opr)
   !< `+` operator.
   class(integrand_ladvection), intent(in) :: lhs    !< Left hand side.
   class(integrand_object),     intent(in) :: rhs    !< Right hand side.
   real(R_P), allocatable                  :: opr(:) !< Operator result.

   select type(rhs)
   class is(integrand_ladvection)
     opr = lhs%u + rhs%u
   endselect
   endfunction integrand_add_integrand

   pure function integrand_add_real(lhs, rhs) result(opr)
   !< `+ real` operator.
   class(integrand_ladvection), intent(in) :: lhs     !< Left hand side.
   real(R_P),                   intent(in) :: rhs(1:) !< Right hand side.
   real(R_P), allocatable                  :: opr(:)  !< Operator result.

   opr = lhs%u + rhs
   endfunction integrand_add_real

   pure function real_add_integrand(lhs, rhs) result(opr)
   !< `real +` operator.
   real(R_P),                   intent(in) :: lhs(1:) !< Left hand side.
   class(integrand_ladvection), intent(in) :: rhs     !< Left hand side.
   real(R_P), allocatable                  :: opr(:)  !< Operator result.

   opr = lhs + rhs%U
   endfunction real_add_integrand

   ! *
   pure function integrand_multiply_integrand(lhs, rhs) result(opr)
   !< `*` operator.
   class(integrand_ladvection), intent(in) :: lhs    !< Left hand side.
   class(integrand_object),     intent(in) :: rhs    !< Right hand side.
   real(R_P), allocatable                  :: opr(:) !< Operator result.

   select type(rhs)
   class is(integrand_ladvection)
     opr = lhs%U * rhs%U
   endselect
   endfunction integrand_multiply_integrand

   pure function integrand_multiply_real(lhs, rhs) result(opr)
   !< `* real_scalar` operator.
   class(integrand_ladvection), intent(in) :: lhs     !< Left hand side.
   real(R_P),                   intent(in) :: rhs(1:) !< Right hand side.
   real(R_P), allocatable                  :: opr(:)  !< Operator result.

   opr = lhs%U * rhs
   endfunction integrand_multiply_real

   pure function real_multiply_integrand(lhs, rhs) result(opr)
   !< `real_scalar *` operator.
   class(integrand_ladvection), intent(in) :: rhs     !< Right hand side.
   real(R_P),                   intent(in) :: lhs(1:) !< Left hand side.
   real(R_P), allocatable                  :: opr(:)  !< Operator result.

   opr = lhs * rhs%U
   endfunction real_multiply_integrand

   pure function integrand_multiply_real_scalar(lhs, rhs) result(opr)
   !< `* real_scalar` operator.
   class(integrand_ladvection), intent(in) :: lhs    !< Left hand side.
   real(R_P),                   intent(in) :: rhs    !< Right hand side.
   real(R_P), allocatable                  :: opr(:) !< Operator result.

   opr = lhs%U * rhs
   endfunction integrand_multiply_real_scalar

   pure function real_scalar_multiply_integrand(lhs, rhs) result(opr)
   !< `real_scalar *` operator.
   real(R_P),                   intent(in) :: lhs    !< Left hand side.
   class(integrand_ladvection), intent(in) :: rhs    !< Right hand side.
   real(R_P), allocatable                  :: opr(:) !< Operator result.

   opr = lhs * rhs%U
   endfunction real_scalar_multiply_integrand

   ! -
   pure function integrand_sub_integrand(lhs, rhs) result(opr)
   !< `-` operator.
   class(integrand_ladvection), intent(in) :: lhs    !< Left hand side.
   class(integrand_object),     intent(in) :: rhs    !< Right hand side.
   real(R_P), allocatable                  :: opr(:) !< Operator result.

   select type(rhs)
   class is(integrand_ladvection)
     opr = lhs%U - rhs%U
   endselect
   endfunction integrand_sub_integrand

   pure function integrand_sub_real(lhs, rhs) result(opr)
   !< `- real` operator.
   class(integrand_ladvection), intent(in) :: lhs     !< Left hand side.
   real(R_P),                   intent(in) :: rhs(1:) !< Right hand side.
   real(R_P), allocatable                  :: opr(:)  !< Operator result.

   opr = lhs%U - rhs
   endfunction integrand_sub_real

   pure function real_sub_integrand(lhs, rhs) result(opr)
   !< `real -` operator.
   real(R_P),                   intent(in) :: lhs(1:) !< Left hand side.
   class(integrand_ladvection), intent(in) :: rhs     !< Left hand side.
   real(R_P), allocatable                  :: opr(:)  !< Operator result.

   opr = lhs - rhs%U
   endfunction real_sub_integrand

   ! =
   subroutine assign_integrand(lhs, rhs)
   !< `=` operator.
   class(integrand_ladvection), intent(inout) :: lhs !< Left hand side.
   class(integrand_object),     intent(in)    :: rhs !< Right hand side.

   select type(rhs)
   class is(integrand_ladvection)
      lhs%w_scheme   = rhs%w_scheme
      lhs%weno_order = rhs%weno_order
      lhs%weno_eps   = rhs%weno_eps
      lhs%CFL        = rhs%CFL
      lhs%Ni         = rhs%Ni
      lhs%Ng         = rhs%Ng
      lhs%length     = rhs%length
      lhs%Dx         = rhs%Dx
      lhs%a          = rhs%a
      if (allocated(rhs%u)) then
         lhs%u = rhs%u
      else
         if (allocated(lhs%u)) deallocate(lhs%u)
      endif
      if (allocated(rhs%interpolator)) then
         if (allocated(lhs%interpolator)) then
            call lhs%interpolator%destroy
            deallocate(lhs%interpolator)
         endif
         allocate(lhs%interpolator, mold=rhs%interpolator)
         lhs%interpolator = rhs%interpolator
      else
         if (allocated(lhs%interpolator)) deallocate(lhs%interpolator)
      endif
      lhs%initial_state = rhs%initial_state
   endselect
   endsubroutine assign_integrand

   pure subroutine assign_real(lhs, rhs)
   !< Assign one real to an advection field.
   class(integrand_ladvection), intent(inout) :: lhs     !< Left hand side.
   real(R_P),                   intent(in)    :: rhs(1:) !< Right hand side.

   lhs%u = rhs
   endsubroutine assign_real

   ! private methods
   pure subroutine impose_boundary_conditions(self, u)
   !< Impose boundary conditions.
   class(integrand_ladvection), intent(in)    :: self          !< Advection field.
   real(R_P),                   intent(inout) :: u(1-self%Ng:) !< Conservative variables.
   integer(I_P)                               :: i             !< Space counter.

   do i=1-self%Ng, 0
      u(i) = u(self%Ni+i)
   enddo

   do i=self%Ni+1, self%Ni+self%Ng
      u(i) = u(i-self%Ni)
   enddo
   endsubroutine impose_boundary_conditions

   subroutine reconstruct_interfaces(self, conservative, r_conservative)
   !< Reconstruct interfaces states.
   class(integrand_ladvection), intent(in)    :: self                         !< Advection field.
   real(R_P),                   intent(in)    :: conservative(1-self%Ng:)     !< Conservative variables.
   real(R_P),                   intent(inout) :: r_conservative(1:, 0:)       !< Reconstructed conservative vars.
   real(R_P)                                  :: C(1:2, 1-self%Ng:-1+self%Ng) !< Stencils.
   real(R_P)                                  :: CR(1:2)                      !< Reconstrcuted intrafaces.
   integer(I_P)                               :: i                            !< Counter.
   integer(I_P)                               :: j                            !< Counter.
   integer(I_P)                               :: f                            !< Counter.

   select case(self%weno_order)
   case(1) ! 1st order piecewise constant reconstruction
      do i=0, self%Ni+1
         r_conservative(1, i) = conservative(i)
         r_conservative(2, i) = r_conservative(1, i)
      enddo
   case(3, 5, 7, 9, 11, 13, 15, 17) ! 3rd-17th order WENO reconstruction
      do i=0, self%Ni+1
         do j=i+1-self%Ng, i-1+self%Ng
            do f=1, 2
               C(f, j-i) = conservative(j)
            enddo
         enddo
         call self%interpolator%interpolate(stencil=C(:, :), interpolation=CR(:))
         do f=1, 2
            r_conservative(f, i)  = CR(f)
         enddo
      enddo
   endselect
   endsubroutine reconstruct_interfaces

   subroutine set_square_wave_initial_state(self)
   !< Set initial state as a square wave.
   class(integrand_ladvection), intent(inout) :: self !< Advection field.
   real(R_P)                                  :: x    !< Cell center x-abscissa values.
   integer(I_P)                               :: i    !< Space counter.

   if (allocated(self%u)) deallocate(self%u) ; allocate(self%u(1:self%Ni))
   do i=1, self%Ni
      x = self%Dx * i - 0.5_R_P * self%Dx
      if     (x < 0.25_R_P) then
         self%u(i) = 0._R_P
      elseif (0.25_R_P <= x .and. x < 0.75_R_P) then
         self%u(i) = 1._R_P
      else
         self%u(i) = 0._R_P
      endif
   enddo
   endsubroutine set_square_wave_initial_state

   subroutine set_sin_wave_initial_state(self)
   !< Set initial state as a sin wave.
   class(integrand_ladvection), intent(inout) :: self                   !< Advection field.
   real(R_P)                                  :: x                      !< Cell center x-abscissa values.
   real(R_P), parameter                       :: pi=4._R_P*atan(1._R_P) !< Pi greek.
   integer(I_P)                               :: i                      !< Space counter.

   if (allocated(self%u)) deallocate(self%u) ; allocate(self%u(1:self%Ni))
   do i=1, self%Ni
      x = self%Dx * i - 0.5_R_P * self%Dx
      self%u(i) = sin(x * 2 * pi)
   enddo
   endsubroutine set_sin_wave_initial_state
endmodule foodie_test_integrand_ladvection
