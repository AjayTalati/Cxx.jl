using Cxx
using Base.Test

# Issue 37 - Assertion failure when calling function declared `extern "C"`
cxx"""
extern "C" {
    void foo37() {
    }
}
"""
@cxx foo37()

# Constnes in template arguments - issue #33
cxx"""
#include <map>
#include <string>

typedef std::map<std::string, std::string> Map;

Map getMap()
{
    return Map({ {"hello", "world"}, {"everything", "awesome"} });
}
int dumpMap(Map m)
{
    return 1;
}
"""
m = @cxx getMap()
@test (@cxx dumpMap(m)) == 1

# Reference return (#50)
cxx"""
int x50 = 6;
int &bar50(int *foo) {
    return *foo;
}
"""
@cxx bar50(@cxx &x50)

# Global Initializers (#53)
cxx"""
#include <vector>

std::vector<int> v(10);
"""
@test icxx"v.size();" == 10

# References to functions (#51)
cxx"""
void foo51() {}
"""

@test_throws ErrorException (@cxx foo51)
@test isa((@cxx &foo51),Cxx.CppFptr)

# References to member functions (#55)
cxx"""
class foo55 {
    foo55() {};
public:
    void bar() {};
};
"""
@test isa((@cxx &foo55::bar),Cxx.CppMFptr)

cxx"""
class bar55 {
    bar55() {};
public:
    double bar(int) { return 0.0; };
};
"""
@test isa((@cxx &bar55::bar),Cxx.CppMFptr)

# booleans as template arguments
cxx"""
template < bool T > class baz {
    baz() {};
public:
    void bar() {};
};
"""

@test isa((@cxx &baz{false}::bar),Cxx.CppMFptr)

# Includes relative to the source directory (#48)
macro test48_str(x,args...)
    return length(args) > 0
end
if test48" "
    cxx"""
    #include "./incpathtest.inc"
    """
    @test (@cxx incpathtest) == 1

    function foo48()
    icxx"""
    #include "./incpathtest.inc"
    return incpathtest;
    """
    end
    @test foo48() == 1
end

# Enum type translation
cxx"""
enum EnumTest {
    EnumA, EnumB, EnumC
};
bool enumfoo(EnumTest foo) {
    return foo == EnumB;
}
"""
@assert (@cxx enumfoo(@cxx EnumB))

# Members with non-trivial copy constructor
cxx"""
#include <vector>
class memreffoo {
public:
    memreffoo(int val) : bar(0) {
        bar.push_back(val);
    };
    std::vector<int> bar;
};
"""
memreffoo = @cxxnew memreffoo(5)
memrefbar = @cxx memreffoo->bar
@assert isa(memrefbar,Cxx.CppValue)
@assert (@cxx memrefbar->size()) == 1

# Anonymous structs are referenced by typedef if possible.
cxx"""
typedef struct {
    int foo;
} anonttest;
anonttest *anonttestf()
{
    return new anonttest{ .foo = 0};
}
"""

@assert typeof(@cxx anonttestf()) == pcpp"anonttest"

# Operator overloading (#102)
cxx"""
typedef struct {
    int x;
} foo102;

foo102 operator+ (const foo102& x, const foo102& y) {
    return { .x = x.x + y.x };
}
"""

x = icxx"foo102{ .x = 1 };"
y = icxx"foo102{ .x = 2 };"
z = @cxx x + y

@assert icxx" $z.x == 3; "

z = x + y
@assert icxx" $z.x == 3; "

# Anonymous enums (#118)
cxx""" enum { kFalse118 = 0, kTrue118 = 1 }; """
@assert icxx" kTrue118; " == 1

# UInt8 builtin (#119)
cxx""" void foo119(char value) {} """
@cxx foo119(UInt8(0))

# Enums should be comparable with integers
cxx""" enum myCoolEnum { OneValue = 1 }; """
@assert icxx" OneValue; " == 1

# Converting julia data
buf = IOBuffer()
@assert pointer_from_objref(buf) == icxx"""(void*)$(jpcpp"jl_value_t"(buf));"""

# Exception handling
try
    icxx" throw 20; "
    @assert false
catch e
    buf = IOBuffer();
    showerror(buf,e)
    @assert takebuf_string(buf) == "20"
end

cxx"""
class test_exception : public std::exception
{
public:
    int x;
    test_exception(int x) : x(x) {};
};
"""

import Base: showerror
@exception function showerror(io::IO, e::rcpp"test_exception")
    print(io, icxx"$e.x;")
end

try
    icxx" throw test_exception(5); "
    @assert false
catch e
    buf = IOBuffer();
    showerror(buf,e)
    @assert takebuf_string(buf) == "5"
end


# Memory management
cxx"""
static int testDestructCounter = 0;
struct testDestruct {
    int x;
    testDestruct(int x) : x(x) {};
    ~testDestruct() { testDestructCounter += x; };
};
"""
X = icxx"return testDestruct{10};"
finalize(X)
@test icxx"testDestructCounter;" == 10

# Template dispatch
foo{T}(x::cxxt"std::vector<$T>") = icxx"$x.size();"
@test foo(icxx"std::vector<uint64_t>{0};") == 1
@test foo(icxx"std::vector<uint64_t>{};") == 0
