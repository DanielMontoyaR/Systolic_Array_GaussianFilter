`timescale 1ns / 1ps

module RAM_Loader_Prueba #(
    parameter RAM_ADDR_WIDTH = 6,   // 64 posiciones (0-63)
    parameter RAM_DATA_WIDTH = 8,
    parameter PE_DATA_WIDTH = 16,
    parameter DEPTH = 4             // Tamaño del arreglo sistólico (4x4)
)(
    input logic clk,
    input logic reset,
    input logic start,
	 input logic tpu_ready,       // Nueva entrada: TPU listo para nuevos datos
    output logic [PE_DATA_WIDTH*DEPTH-1:0] data_out,
    output logic data_valid,
    output logic done,
	 output logic load_next       // Nueva salida: Solicitud de siguiente bloque
	 
);

    // --- Señales internas para la RAM ---
    logic [RAM_ADDR_WIDTH-1:0] ram_address;
    logic [RAM_DATA_WIDTH-1:0] ram_data;
    
    // --- Instancia de la RAM ---
    ram1 ram_inst (
        .address(ram_address),
        .clock(clk),
        .data(8'h00),       // No usado en modo lectura
        .wren(1'b0),        // Siempre lectura (0)
        .q(ram_data)        // Datos de salida de la RAM
    );

    // --- Estados ---
     typedef enum logic [2:0] {  // Ampliado a 3 bits
        IDLE,
        LOAD,
        WAIT_TPU,      // Nuevo estado: esperar a que TPU procese
        FINISH,
        DONE_ST
    } state_t;

    state_t current_state, next_state;
    
    // --- Registros ---
    logic [RAM_ADDR_WIDTH-1:0] base_addr;
    logic [1:0] word_counter;
    logic [PE_DATA_WIDTH-1:0] data_buffer [DEPTH];
    logic last_block;
    logic [1:0] read_delay;  // Contador para manejar latencia de RAM
    logic first_read;        // Bandera para primer lectura
    
    // --- Lógica de estado ---
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            base_addr <= 0;
            word_counter <= 0;
            data_valid <= 0;
            done <= 0;
            last_block <= 0;
            read_delay <= 0;
            first_read <= 1;
            // Inicialización explícita del buffer
            for (int i = 0; i < DEPTH; i++) begin
                data_buffer[i] <= 0;
            end
        end else begin
            current_state <= next_state;
            
            case (current_state)
                LOAD: begin
                    if (first_read) begin
                        // Esperar 3 ciclos para el primer dato
                        if (read_delay < 3) begin
                            read_delay <= read_delay + 1;
                        end else begin
                            // Capturar dato de la RAM (extendido a 16 bits)
                            data_buffer[word_counter] <= {8'h00, ram_data};
                            first_read <= 0;
                            read_delay <= 0;
                            
                            if (word_counter == DEPTH-1) begin
                                word_counter <= 0;
                                base_addr <= base_addr + DEPTH;
                                data_valid <= 1;
                                last_block <= (base_addr + DEPTH >= 2**RAM_ADDR_WIDTH - DEPTH);
                            end else begin
                                word_counter <= word_counter + 1;
                                data_valid <= 0;
                            end
                        end
                    end else begin
                        if (read_delay < 2) begin
                            read_delay <= read_delay + 1;
                        end else begin
                            // Capturar dato de la RAM (extendido a 16 bits)
                            data_buffer[word_counter] <= {8'h00, ram_data};
                            read_delay <= 0;
                            
                            if (word_counter == DEPTH-1) begin
                                word_counter <= 0;
                                base_addr <= base_addr + DEPTH;
                                data_valid <= 1;
                                last_block <= (base_addr + DEPTH >= 2**RAM_ADDR_WIDTH - DEPTH);
                            end else begin
                                word_counter <= word_counter + 1;
                                data_valid <= 0;
                            end
                        end
                    end
                end
                
                FINISH: begin
                    data_valid <= 1;  // Último bloque válido
                end
                
                DONE_ST: begin
                    done <= 1;        // Señal de finalización
                    data_valid <= 0;
                end
                
                default: begin  // IDLE
                    data_valid <= 0;
                end
            endcase
        end
    end
    
    // Lógica de próximo estado modificada
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE:     if (start) next_state = LOAD;
            LOAD:     if (last_block && word_counter == DEPTH-1 && read_delay == 2) 
                          next_state = FINISH;
                      else if (word_counter == DEPTH-1 && read_delay == 2) 
                          next_state = WAIT_TPU;
            WAIT_TPU: if (tpu_ready) next_state = LOAD;
            FINISH:   next_state = DONE_ST;
            DONE_ST:  next_state = IDLE;
        endcase
    end
    
    // --- Dirección de RAM ---
    assign ram_address = (current_state == LOAD) ? (base_addr + word_counter) : 0;
    
    // --- Salida concatenada ---
    assign data_out = {data_buffer[3], data_buffer[2], data_buffer[1], data_buffer[0]};
	 assign load_next = (current_state == WAIT_TPU);
endmodule