using Test
using JotTest1

input = Dict("double" => 0.1)
input_doubled = JotTest1.response_func(input)
@test isa(input_doubled, Float64)
@test input_doubled == 0.2

input = Dict("add suffix" => "suffixme_")
input_suffixed = JotTest1.response_func(input)
@test isa(input_suffixed, String)
