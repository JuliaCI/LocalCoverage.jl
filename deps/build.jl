using Compat

try
    verstring = read(`genhtml -v`, String)
    m = match(r"^.*(\d.\d+)$", verstring)
    if m ≡ nothing
        warn("Could not parse `genhtml -v` version information, please open an issue.")
    else
        ver = VersionNumber(m[1])
        OLDVERWARN = """
        The installed version of `genhtml` is $ver, HTML generation may not work.
        See https://github.com/tpapp/LocalCoverage.jl/issues/1 for workarounds.
        """
        ver ≥ v"1.12" || warn(OLDVERWARN)
    end
catch
    warn("Could not find `genhtml`, you need to install it to generate HTML reports.")
end
