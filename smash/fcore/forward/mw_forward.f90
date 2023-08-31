!%      (MW) Module Wrapped.
!%
!%      Subroutine
!%      ----------
!%
!%      - forward_run
!%      - forward_run_d
!%      - forward_run_b
!%      - multiple_forward_run_sample_to_parameters
!%      - multiple_forward_run_prgress
!%      - multiple_forward_run

module mw_forward

    use md_constant, only: sp
    use mwd_setup, only: SetupDT
    use mwd_mesh, only: MeshDT
    use mwd_input_data, only: Input_DataDT
    use mwd_parameters, only: ParametersDT
    use mwd_output, only: OutputDT
    use mwd_options, only: OptionsDT
    use mwd_returns, only: ReturnsDT

    implicit none

contains

    subroutine forward_run(setup, mesh, input_data, parameters, output, options, returns)

        implicit none

        type(SetupDT), intent(in) :: setup
        type(MeshDT), intent(in) :: mesh
        type(Input_DataDT), intent(in) :: input_data
        type(ParametersDT), intent(inout) :: parameters
        type(OutputDT), intent(inout) :: output
        type(OptionsDT), intent(in) :: options
        type(ReturnsDT), intent(inout) :: returns

        call base_forward_run(setup, mesh, input_data, parameters, output, options, returns)

    end subroutine forward_run

    subroutine forward_run_d(setup, mesh, input_data, parameters, parameters_d, output, output_d, options, returns)

        implicit none

        type(SetupDT), intent(in) :: setup
        type(MeshDT), intent(in) :: mesh
        type(Input_DataDT), intent(in) :: input_data
        type(ParametersDT), intent(inout) :: parameters, parameters_d
        type(OutputDT), intent(inout) :: output, output_d
        type(OptionsDT), intent(in) :: options
        type(ReturnsDT), intent(inout) :: returns

        call base_forward_run_d(setup, mesh, input_data, parameters, parameters_d, output, output_d, options, returns)

    end subroutine forward_run_d

    subroutine forward_run_b(setup, mesh, input_data, parameters, parameters_b, output, output_b, options, returns)

        implicit none

        type(SetupDT), intent(in) :: setup
        type(MeshDT), intent(in) :: mesh
        type(Input_DataDT), intent(in) :: input_data
        type(ParametersDT), intent(inout) :: parameters, parameters_b
        type(OutputDT), intent(inout) :: output, output_b
        type(OptionsDT), intent(in) :: options
        type(ReturnsDT), intent(inout) :: returns

        call base_forward_run_b(setup, mesh, input_data, parameters, parameters_b, output, output_b, options, returns)

    end subroutine forward_run_b

    subroutine multiple_forward_run_sample_to_parameters(sample, samples_kind, samples_ind, parameters)

        implicit none

        real(sp), dimension(:), intent(in) :: sample
        integer, dimension(size(sample)), intent(in) :: samples_kind, samples_ind
        type(ParametersDT), intent(inout) :: parameters

        integer :: i

        do i = 1, size(sample)

            select case (samples_kind(i))

            case (0)
                parameters%opr_parameters%values(:, :, samples_ind(i)) = sample(i)

            case (1)
                parameters%opr_initial_states%values(:, :, samples_ind(i)) = sample(i)

                ! Should be unreachable
            case default

            end select

        end do

    end subroutine multiple_forward_run_sample_to_parameters

    subroutine multiple_forward_run_progess(iter, niter)

        implicit none

        integer, intent(in) :: iter, niter

        integer :: per

        per = 100*iter/niter

        if (per .ne. 100*(iter - 1)/niter) then

            write (*, "(a,4x,a,1x,i0,a,i0,1x,a,i0,a)", advance="no") achar(13), "Forward Run", iter, "/", niter, "(", per, "%)"

        end if

        if (iter == niter) write (*, "(a)") new_line("")

    end subroutine multiple_forward_run_progess

    subroutine multiple_forward_run(setup, mesh, input_data, parameters, output, options, &
    & samples, samples_kind, samples_ind, cost, q)

        implicit none

        type(SetupDT), intent(in) :: setup
        type(MeshDT), intent(in) :: mesh
        type(Input_DataDT), intent(in) :: input_data
        type(ParametersDT), intent(inout) :: parameters
        type(OutputDT), intent(inout) :: output
        type(OptionsDT), intent(inout) :: options
        real(sp), dimension(:, :), intent(in) :: samples
        integer, dimension(size(samples, 1)) :: samples_kind, samples_ind
        real(sp), dimension(size(samples, 2)), intent(inout) :: cost
        real(sp), dimension(mesh%ng, setup%ntime_step, size(samples, 2)), intent(inout) :: q

        integer :: i, iter, niter, ncpu
        logical :: verbose
        type(ParametersDT) :: parameters_thread
        type(OutputDT) :: output_thread
        type(ReturnsDT) :: returns

        niter = size(samples, 2)
        iter = 0

        ! Trigger parallel in multiple forward run and not inside forward run
        ncpu = options%comm%ncpu
        options%comm%ncpu = 1

        ! Deactivate other verbose
        verbose = options%comm%verbose
        options%comm%verbose = .false.

        if (verbose) call multiple_forward_run_progess(iter, niter)

        !$OMP parallel do schedule(static) num_threads(ncpu) &
        !$OMP& shared(setup, mesh, input_data, parameters, output, options, returns) &
        !$OMP& shared(samples, samples_kind, samples_ind, iter, niter, cost, q) &
        !$OMP& private(i, parameters_thread, output_thread)
        do i = 1, niter

            parameters_thread = parameters
            output_thread = output

            call multiple_forward_run_sample_to_parameters(samples(:, i), samples_kind, samples_ind, parameters_thread)

            call forward_run(setup, mesh, input_data, parameters_thread, output_thread, options, returns)

            !$OMP critical
            cost(i) = output_thread%cost
            q(:, :, i) = output_thread%sim_response%q

            iter = iter + 1
            if (verbose) call multiple_forward_run_progess(iter, niter)
            !$OMP end critical

        end do
        !$OMP end parallel do

    end subroutine multiple_forward_run

end module mw_forward
