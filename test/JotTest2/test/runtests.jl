using Test
using JotTest2

input = Dict("double" => 0.1)
input_doubled = JotTest2.response_func(input)
@test isa(input_doubled, Float64)
@test input_doubled == 0.2

input = Dict("add suffix" => "suffixme_")
input_suffixed = JotTest2.response_func(input)
@test isa(input_suffixed, String)
