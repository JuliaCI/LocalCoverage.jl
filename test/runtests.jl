using LocalCoverage, Test
using FileCmp

import Pkg

Pkg.activate("./DummyPackage/")

const pkg = "DummyPackage"      # we test the package with a dummy created for this purpose

table_header = r"Filename\s+.\s+Lines\s+.\s+Hit\s+.\s+Miss\s+.\s+%"
table_line = r"(?<!\/|\\\\)src(\/|\\\\)[\w\/]+\.jl?\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+%"
table_footer = r"TOTAL\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+\s+.\s+\d+%"

covdir = normpath(joinpath(@__DIR__, "DummyPackage", "coverage"))

function test_coverage(pkg; 
                       run_test = true, 
                       test_args = [""], 
                       folder_list = ["src"], 
                       file_list = [],
                       css = nothing,
                       should_throw = false)
    @info "Testing coverage for $pkg" test_args folder_list file_list
    clean_coverage(pkg)
    @test isdir(LocalCoverage.pkgdir(pkg))
    lcovtrace = joinpath(covdir, "lcov.info")
    @test !isfile(lcovtrace)

    if should_throw
        @test_throws Pkg.Types.PkgError generate_coverage(pkg;
                                                          run_test=run_test,
                                                          test_args=test_args,
                                                          folder_list=folder_list,
                                                          file_list=file_list)
    else
        cov = generate_coverage(pkg; 
                                run_test = run_test, 
                                test_args = test_args, 
                                folder_list = folder_list, 
                                file_list = file_list)

        buffer = IOBuffer()
        show(buffer, cov)
        table = String(take!(buffer))
        println(table)
        @test !isnothing(match(table_header, table))
        @test !isnothing(match(table_line, table))
        @test !isnothing(match(table_footer, table))

        @info "Printing coverage information for visual debugging"
        show(stdout, cov)
        show(IOContext(stdout, :print_gaps => true), cov)
    end

    xmltrace = joinpath(covdir,"lcov.xml")
    write_lcov_to_xml(xmltrace, lcovtrace)
    open(xmltrace, "r") do io
        header = readline(io)
        doctype = readline(io)
        @test header == """<?xml version="1.0" encoding="UTF-8"?>"""
        @test startswith(doctype, "<!DOCTYPE coverage")
    end

    if !isnothing(Sys.which("genhtml"))
        mktempdir() do dir
            html_coverage(pkg, dir = dir, css = css)
            @test isfile(joinpath(dir, "index.html"))
            isnothing(css) ||
                @test filecmp(joinpath(dir, "gcov.css"), css)
        end
    end

    @test isfile(lcovtrace)
    rm(covdir, recursive = true)
end

@testset verbose = true "Testing coverage with" begin
    @testset "default values" begin
        test_coverage("DummyPackage")
    end

    @testset "test_args and file_list" begin
        test_coverage("DummyPackage"; 
                    test_args = ["testset 2"], 
                    file_list = [joinpath(dirname(@__FILE__), "DummyPackage", "src", "qux.jl")])
    end

    @testset "test_args and folder_list" begin
        test_coverage("DummyPackage"; 
                    test_args = ["testset 1"], 
                    folder_list = [joinpath(dirname(@__FILE__), "DummyPackage", "src", "corge")])
    end

    @testset "test_args and file_list and folder_list" begin
        test_coverage("DummyPackage"; 
                    test_args = ["testset 1", "testset 2"], 
                    folder_list = [joinpath(dirname(@__FILE__), "DummyPackage", "src", "corge")],
                    file_list = [joinpath(dirname(@__FILE__), "DummyPackage", "src", "qux.jl")])
    end

    @testset "custom CSS" begin
        @test_throws TypeError test_coverage("DummyPackage", css=1)
        test_coverage("DummyPackage", css=joinpath(dirname(@__FILE__), "dummy.css"))
    end

    @testset "failing tests" begin
        test_coverage("DummyPackage"; test_args = ["testset 3"], should_throw = true)
    end
end

@test LocalCoverage.find_gaps([nothing, 0, 0, 0, 2, 3, 0, nothing, 0, 3, 0, 6, 2]) ==
    [2:4, 7:7, 9:9, 11:11]
