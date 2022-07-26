!%      This module `mw_adjoint_test` encapsulates all SMASH adjoint_test.
!%      This module is wrapped.
!%
!%      contains
!%
!%      [1] scalar_product_test
!%      [2] gradient_test

module mw_adjoint_test
    
    use mwd_common !% only: sp, dp, lchar, np, np
    use mwd_setup !% only: SetupDT
    use mwd_mesh  !% only: MeshDT
    use mwd_input_data !% only: Input_DataDT
    use mwd_parameters !%  only: ParametersDT, parameters_to_matrix, matrix_to_parameters
    use mwd_states !% only: StatesDT
    use mwd_output !% only: OutputDT
    
    implicit none
    
    contains
    
        !% Calling forward_d from forward/forward_d.f90
        !% Calling forward_b from forward/forward_b.f90
        subroutine scalar_product_test(setup, mesh, input_data, parameters, states, output)
            
            implicit none
            
            type(SetupDT), intent(inout) :: setup
            type(MeshDT), intent(inout) :: mesh
            type(Input_DataDT), intent(inout) :: input_data
            type(ParametersDT), intent(inout) :: parameters
            type(StatesDT), intent(inout) :: states
            type(OutputDT), intent(inout) :: output
            
            type(ParametersDT) :: parameters_bgd, parameters_d, parameters_b
            type(StatesDT) ::  states_bgd, states_d, states_b
            type(OutputDT) ::  output_d, output_b
            real(sp) :: cost, cost_d, cost_b
            real(sp), dimension(mesh%nrow, mesh%ncol, np) :: parameters_d_matrix, parameters_b_matrix
            real(sp), dimension(mesh%nrow, mesh%ncol, ns) :: states_d_matrix

            
            write(*,'(a)') "</> Scalar Product Test"
            
            parameters_bgd = parameters
            states_bgd = states
            
            call ParametersDT_initialise(parameters_d, mesh)
            call ParametersDT_initialise(parameters_b, mesh)
            
            call StatesDT_initialise(states_d, mesh)
            call StatesDT_initialise(states_b, mesh)
            
            call OutputDT_initialise(output_d, setup, mesh)
            call OutputDT_initialise(output_b, setup, mesh)
            
            call parameters_to_matrix(parameters_d, parameters_d_matrix)
            call states_to_matrix(states_d, states_d_matrix)
            
            parameters_d_matrix = 1._sp
            states_d_matrix = 0._sp
            
            call matrix_to_parameters(parameters_d_matrix, parameters_d)
            call matrix_to_states(states_d_matrix, states_d)
            
            write(*,'(4x,a)') "Tangent Linear Model dY  = (dM/dk) (k) . dk"
            
            call forward_d(setup, mesh, input_data, parameters, &
            & parameters_d, parameters_bgd, states, states_d, &
            & output, output_d, cost, cost_d)
            
            states = states_bgd
            cost_b = 1._sp
            
            write(*,'(4x,a)') "Adjoint Model        dk* = (dM/dk)* (k) . dY*"
            
            call forward_b(setup, mesh, input_data, parameters, &
            & parameters_b, parameters_bgd, states, states_b, &
            & output, output_b, cost, cost_b)
            
            states = states_bgd
            
            call parameters_to_matrix(parameters_b, parameters_b_matrix)
            
            !% cost_b reset at the end of the forward_b ...
            !% No perturbation has been set to states_d
            output%sp1 = 1._sp * cost_d
            
            output%sp2 = sum(parameters_b_matrix * parameters_d_matrix)
            
            write(*,'(4x,a,f12.8)') "<dY*, dY> (sp1) = ", output%sp1
            write(*,'(4x,a,f12.8)') "<dk*, dk> (sp2) = ", output%sp2
            write(*,'(4x,a,f12.8)') "Relative Error  = ", (output%sp1 - output%sp2) &
            & / output%sp1
        
        end subroutine scalar_product_test
        
        !% Calling forward from forward/forward.f90
        !% Calling forward_b from forward/forward_b.f90
        subroutine gradient_test(setup, mesh, input_data, parameters, states, output)
        
            implicit none
            
            type(SetupDT), intent(inout) :: setup
            type(MeshDT), intent(inout) :: mesh
            type(Input_DataDT), intent(inout) :: input_data
            type(ParametersDT), intent(inout) :: parameters
            type(StatesDT), intent(inout) :: states
            type(OutputDT), intent(inout) :: output
            
            type(ParametersDT) :: parameters_bgd, parameters_b
            type(StatesDT) :: states_bgd, states_b
            type(OutputDT) :: output_b
            real(sp) :: cost, cost_b
            real(sp), dimension(mesh%nrow, mesh%ncol, np) :: parameters_matrix, parameters_b_matrix
            real(sp) :: yk, yadk, dk
            integer :: n
            
            write(*,'(a)') "</> Gradient Test"
            
            if (.not. allocated(output%an)) allocate(output%an(16))
    
            if (.not. allocated(output%ian)) allocate(output%ian(16))
            
            parameters_bgd = parameters
            states_bgd = states
            dk = 1._sp
            
            call ParametersDT_initialise(parameters_b, mesh)
            call StatesDT_initialise(states_b, mesh)
            call OutputDT_initialise(output_b, setup, mesh)
            
            write(*,'(4x,a)') "Forward Model Y    = M (k)"
            
            call forward(setup, mesh, input_data, parameters, &
            & parameters_bgd, states, output, cost)
            
            states = states_bgd
            
            yk = cost
            
            cost_b = 1._sp
            
            write(*,'(4x,a)') "Adjoint Model dk*  = (dM/dk)* (k) . dY*"
            
            call forward_b(setup, mesh, input_data, parameters, &
            & parameters_b, parameters_bgd, states, states_b, &
            & output, output_b, cost, cost_b)
            
            states = states_bgd
            
            call parameters_to_matrix(parameters_b, parameters_b_matrix)
            
            write(*,'(4x,a)') "Forward Model Yadk = M (k + a dk)"
            
            do n=1, 16
            
                output%an(n) = 2._sp ** (- (n - 1))
            
                call parameters_to_matrix(parameters_bgd, parameters_matrix)
                
                parameters_matrix = parameters_matrix + output%an(n) * dk
                
                call matrix_to_parameters(parameters_matrix, parameters)
                
                call forward(setup, mesh, input_data, parameters, &
                & parameters_bgd, states, output, cost)
                
                states = states_bgd
                
                yadk = cost
                
                output%ian(n) = (yadk - yk) / (output%an(n) * sum(parameters_b_matrix * dk)) 
                
                write(*,'(4x,a,f12.8,4x,a,f12.8)') "a = ", output%an(n), "|Ia - 1| = ", abs(output%ian(n) - 1)
                
            end do
            
            write(*,'(4x,a)') "Ia = (Yadk - Y) / (a dk* . dk)"
        
        end subroutine gradient_test
        

end module mw_adjoint_test
