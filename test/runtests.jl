using LocalCoverage, Test
using FileCmp

if isnothing(Sys.which("genhtml"))
    error("Install the genhtml binary for running the unit tests. See the README.md.")
end

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

        # Testing JSON summary generation (low-level)
        jsonsummary = joinpath(covdir, "coverage-summary.json")
        @test !isfile(jsonsummary)
        generate_json_summary(cov, "coverage-summary.json"; test_args = test_args)
        @test isfile(jsonsummary)
        json_content = read(jsonsummary, String)
        @test occursin(test_args == [""] ? "\"total\":" : "\"" * join(test_args, " ") * "\":", json_content)
        @test occursin("\"lines\":", json_content)
        @test occursin("\"statements\":", json_content)
        @test occursin("\"functions\":", json_content)
        @test occursin("\"branches\":", json_content)
        @test occursin("\"total\":", json_content)
        @test occursin("\"pct\":", json_content)
        rm(jsonsummary)
        
        # Test generate_coverage with json_summary=true
        direct_json = joinpath(covdir, "coverage-summary-direct.json")
        @test !isfile(direct_json)
        generate_coverage(pkg;
                          run_test = false,
                          test_args = test_args,
                          folder_list = folder_list,
                          file_list = file_list,
                          json_summary = true,
                          json_summary_filename = "coverage-summary-direct.json")
        @test isfile(direct_json)
        direct_content = read(direct_json, String)
        @test occursin(test_args == [""] ? "\"total\":" : "\"" * join(test_args, " ") * "\":", direct_content)
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

@testset "compare_coverage_json_summaries" begin
    # Mocking old and new JSON string summaries
    old_json = """
    {
      "total": {
        "lines": {"total": 10, "covered": 5, "skipped": 0, "pct": 50.0},
        "statements": {"total": 10, "covered": 5, "skipped": 0, "pct": 50.0},
        "functions": {"total": 10, "covered": 5, "skipped": 0, "pct": 50.0},
        "branches": {"total": 10, "covered": 5, "skipped": 0, "pct": 50.0}
      },
      "src/bar.jl": {
        "lines": {"total": 5, "covered": 2, "skipped": 0, "pct": 40.0},
        "statements": {"total": 5, "covered": 2, "skipped": 0, "pct": 40.0},
        "functions": {"total": 5, "covered": 2, "skipped": 0, "pct": 40.0},
        "branches": {"total": 5, "covered": 2, "skipped": 0, "pct": 40.0}
      }
    }
    """
    
    # Increased coverage scenario
    inc_json = """
    {
      "total": {
        "lines": {"total": 10, "covered": 8, "skipped": 0, "pct": 80.0},
        "statements": {"total": 10, "covered": 8, "skipped": 0, "pct": 80.0},
        "functions": {"total": 10, "covered": 8, "skipped": 0, "pct": 80.0},
        "branches": {"total": 10, "covered": 8, "skipped": 0, "pct": 80.0}
      },
      "src/bar.jl": {
        "lines": {"total": 5, "covered": 4, "skipped": 0, "pct": 80.0},
        "statements": {"total": 5, "covered": 4, "skipped": 0, "pct": 80.0},
        "functions": {"total": 5, "covered": 4, "skipped": 0, "pct": 80.0},
        "branches": {"total": 5, "covered": 4, "skipped": 0, "pct": 80.0}
      }
    }
    """
    
    # Decreased coverage scenario
    dec_json = """
    {
      "total": {
        "lines": {"total": 10, "covered": 2, "skipped": 0, "pct": 20.0},
        "statements": {"total": 10, "covered": 2, "skipped": 0, "pct": 20.0},
        "functions": {"total": 10, "covered": 2, "skipped": 0, "pct": 20.0},
        "branches": {"total": 10, "covered": 2, "skipped": 0, "pct": 20.0}
      },
      "src/bar.jl": {
        "lines": {"total": 5, "covered": 1, "skipped": 0, "pct": 20.0},
        "statements": {"total": 5, "covered": 1, "skipped": 0, "pct": 20.0},
        "functions": {"total": 5, "covered": 1, "skipped": 0, "pct": 20.0},
        "branches": {"total": 5, "covered": 1, "skipped": 0, "pct": 20.0}
      }
    }
    """
    
    # Test JSON string parsing and direct comparison
    @test compare_coverage_json_summaries(old_json, old_json) == true # unchanged is true (not decreased)
    @test compare_coverage_json_summaries(old_json, inc_json) == true # increased is true
    @test compare_coverage_json_summaries(old_json, dec_json) == false # decreased is false
    @test compare_coverage_json_summaries("", old_json) == true # empty string is automatic pass
    @test compare_coverage_json_summaries("nonexistent_summary_file_abc123.json", old_json) == true # missing file is automatic pass
    
    # Test file-based comparison
    mktempdir() do tmp_dir
        old_file = joinpath(tmp_dir, "old.json")
        inc_file = joinpath(tmp_dir, "inc.json")
        dec_file = joinpath(tmp_dir, "dec.json")
        
        write(old_file, old_json)
        write(inc_file, inc_json)
        write(dec_file, dec_json)
        
        @test compare_coverage_json_summaries(old_file, old_file) == true
        @test compare_coverage_json_summaries(old_file, inc_file) == true
        @test compare_coverage_json_summaries(old_file, dec_file) == false
        
        # Test integrated generate_coverage comparison
        cov_dir = joinpath(dirname(@__FILE__), "DummyPackage", "coverage")
        rm(cov_dir; force=true, recursive=true)
        
        # Scenario: old file coverage is lower (20.0%) than generated coverage -> should pass
        cov = generate_coverage("DummyPackage"; run_test=true, json_comparison_summary_filename=dec_file, json_summary_comparison_fail_on_decrease=false)
        @test isfile(joinpath(cov_dir, "coverage-summary.json"))
        
        # Scenario: old file coverage is higher (80.0%) than generated coverage (~28.57%) -> should fail
        @test_throws ErrorException generate_coverage("DummyPackage"; run_test=true, json_comparison_summary_filename=inc_file, json_summary_comparison_fail_on_decrease=true)

        # Scenario: old file is missing -> should pass automatically
        cov = generate_coverage("DummyPackage"; run_test=true, json_comparison_summary_filename="missing_file_abc.json", json_summary_comparison_fail_on_decrease=true)
        @test isfile(joinpath(cov_dir, "coverage-summary.json"))
        
        # Cleanup
        rm(cov_dir; force=true, recursive=true)
    end
end

@test LocalCoverage.find_gaps([nothing, 0, 0, 0, 2, 3, 0, nothing, 0, 3, 0, 6, 2]) ==
    [2:4, 7:7, 9:9, 11:11]

@testset "report_coverage_and_exit" begin
    pkg_root = dirname(@__DIR__)
    dummy_pkg_dir = escape_string(joinpath(@__DIR__, "DummyPackage"))
    
    # 1. Test report_coverage_and_exit(pkg; target_coverage)
    # 1a. Target met (10% target coverage on DummyPackage should meet it and exit 0)
    cmd_met = `$(Base.julia_cmd()) --project=$(pkg_root) -e "using LocalCoverage; using Pkg; Pkg.activate(\"$(dummy_pkg_dir)\"); report_coverage_and_exit(\"DummyPackage\"; target_coverage=10)"`
    p_met = open(cmd_met, "r")
    out_met = read(p_met, String)
    wait(p_met)
    close(p_met)
    @test p_met.exitcode == 0
    @test occursin("Target coverage was met", out_met)
    @test occursin("10%", out_met)
    @test occursin("TOTAL", out_met)  # Summary was printed
    
    # 1b. Target wasn't met (100% target coverage on DummyPackage should fail it and exit 1)
    cmd_unmet = `$(Base.julia_cmd()) --project=$(pkg_root) -e "using LocalCoverage; using Pkg; Pkg.activate(\"$(dummy_pkg_dir)\"); report_coverage_and_exit(\"DummyPackage\"; target_coverage=100)"`
    p_unmet = open(cmd_unmet, "r")
    out_unmet = read(p_unmet, String)
    wait(p_unmet)
    close(p_unmet)
    @test p_unmet.exitcode == 1
    @test occursin("Target coverage wasn't met", out_unmet)
    @test occursin("100%", out_unmet)
    @test occursin("TOTAL", out_unmet)  # Summary was printed
    
    # 1c. Target met but with print_summary = false (summary should not be printed)
    cmd_no_summary = `$(Base.julia_cmd()) --project=$(pkg_root) -e "using LocalCoverage; using Pkg; Pkg.activate(\"$(dummy_pkg_dir)\"); report_coverage_and_exit(\"DummyPackage\"; target_coverage=10, print_summary=false)"`
    p_no_summary = open(cmd_no_summary, "r")
    out_no_summary = read(p_no_summary, String)
    wait(p_no_summary)
    close(p_no_summary)
    @test p_no_summary.exitcode == 0
    @test occursin("Target coverage was met", out_no_summary)
    @test occursin("10%", out_no_summary)
    @test !occursin("TOTAL", out_no_summary)  # Summary was NOT printed
    
    # 1d. Target met with print_gaps = true
    cmd_gaps = `$(Base.julia_cmd()) --project=$(pkg_root) -e "using LocalCoverage; using Pkg; Pkg.activate(\"$(dummy_pkg_dir)\"); report_coverage_and_exit(\"DummyPackage\"; target_coverage=10, print_gaps=true)"`
    p_gaps = open(cmd_gaps, "r")
    out_gaps = read(p_gaps, String)
    wait(p_gaps)
    close(p_gaps)
    @test p_gaps.exitcode == 0
    @test occursin("Target coverage was met", out_gaps)
    @test occursin("10%", out_gaps)
    @test occursin("TOTAL", out_gaps)
    
    # 2. Test report_coverage_and_exit(coverage::PackageCoverage; target_coverage)
    # 2a. Target met (exit 0)
    cmd_cov_met = `$(Base.julia_cmd()) --project=$(pkg_root) -e "using LocalCoverage; using Pkg; Pkg.activate(\"$(dummy_pkg_dir)\"); cov = generate_coverage(\"DummyPackage\"); report_coverage_and_exit(cov; target_coverage=10, print_summary=false)"`
    p_cov_met = open(cmd_cov_met, "r")
    out_cov_met = read(p_cov_met, String)
    wait(p_cov_met)
    close(p_cov_met)
    @test p_cov_met.exitcode == 0
    @test occursin("Target coverage was met", out_cov_met)
    @test occursin("10%", out_cov_met)
    
    # 2b. Target wasn't met (exit 1)
    cmd_cov_unmet = `$(Base.julia_cmd()) --project=$(pkg_root) -e "using LocalCoverage; using Pkg; Pkg.activate(\"$(dummy_pkg_dir)\"); cov = generate_coverage(\"DummyPackage\"); report_coverage_and_exit(cov; target_coverage=100, print_summary=false)"`
    p_cov_unmet = open(cmd_cov_unmet, "r")
    out_cov_unmet = read(p_cov_unmet, String)
    wait(p_cov_unmet)
    close(p_cov_unmet)
    @test p_cov_unmet.exitcode == 1
    @test occursin("Target coverage wasn't met", out_cov_unmet)
    @test occursin("100%", out_cov_unmet)

    # Cleanup generated coverage directory for DummyPackage
    rm(joinpath(@__DIR__, "DummyPackage", "coverage"); force=true, recursive=true)
end


# automated QA
import Aqua
Aqua.test_all(LocalCoverage)
