using Jot
responder = get_responder("./append_string.jl", :append_string, String)
test_data = FunctionTestData("test", "test-y1bcbwgr")
create_jot_sysimage!(responder, test_data)
