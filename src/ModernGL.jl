module ModernGL

function glXGetProcAddress(glFuncName::ASCIIString)
    ccall((:glXGetProcAddress, "libGL.so.1"), Ptr{Void}, (Ptr{Uint8},), glFuncName)
end

function NSGetProcAddress(glFuncName::ASCIIString)
#=
    if this approach doesn't work, I might need to wrap this:
    GLFWglproc _glfwPlatformGetProcAddress(const char* procname)
    {
        CFStringRef symbolName = CFStringCreateWithCString(kCFAllocatorDefault,
                                                           procname,
                                                           kCFStringEncodingASCII);

        GLFWglproc symbol = CFBundleGetFunctionPointerForName(_glfw.nsgl.framework,
                                                              symbolName);

        CFRelease(symbolName);

        return symbol;
    }
=#
    tmp = "_"*glFuncName
    if ccall(:NSIsSymbolNameDefined, Cint, (Ptr{Uint8},), tmp) == 0
        return convert(Ptr{Void}, 0)
    else
        symbol = ccall(:NSLookupAndBindSymbol, Ptr{Void}, (Ptr{Uint8},), tmp)
        return ccall(:NSAddressOfSymbol, Ptr{Void}, (Ptr{Void},), symbol)
    end
end

function wglGetProcAddress(glFuncName::ASCIIString)
    ccall((:wglGetProcAddress, "opengl32"), Ptr{Void}, (Ptr{Uint8},), glFuncName)
end


function getprocaddress(glFuncName::ASCIIString)
    @linux? ( glXGetProcAddress(glFuncName)
        :
        @windows? (wglGetProcAddress(glFuncName)
            :
            @osx? (NSGetProcAddress(glFuncName)
                :error("platform not supported")
            )
        )
    )
end

function getprocaddress_e(glFuncName)
    p = getprocaddress(glFuncName)
    if !isavailable(p)
        error(glFuncName, " not available for your driver, or no valid OpenGL context available")
    end
    p
end

# Test, if an opengl function is available.
# Sadly, this doesn't work for Linux, as glxGetProcAddress
# always returns a non null function pointer, as the function pointers are not depending on an active context.
#

function isavailable(name::Symbol)
    ptr = ModernGL.getprocaddress(ascii(string(name)))
    return isavailable(ptr)
end
function isavailable(ptr::Ptr{Void})
    return !(
        ptr == C_NULL ||
        ptr == convert(Ptr{Void},  1) ||
        ptr == convert(Ptr{Void},  2) ||
        ptr == convert(Ptr{Void},  3))
end



function glfunc_begin()
    @windows_only global glLib = Libdl.dlopen(glLibName)
end

function glfunc_end()
    @windows_only Libdl.dlclose(glLib)
end

# based on getCFun macro
macro glfunc(cFun)
    arguments = map(function (arg)
                        if isa(arg, Symbol)
                            arg = Expr(:(::), arg)
                        end
                        return arg
                    end, cFun.args[1].args[2:end])

    # Get info out of arguments of `cFun`
    argumentNames = map(arg->arg.args[1], arguments)
    returnType    = cFun.args[2]
    inputTypes    = map(arg->arg.args[2], arguments)
    fnName        = cFun.args[1].args[1]
    fnNameStr     = string(fnName)


    ret = quote
        @generated function $fnName($(argumentNames...))
            $(Expr(:quote, :(ccall(getprocaddress_e($fnNameStr), $returnType, ($(inputTypes...),), $(argumentNames...)))))
        end
        $(Expr(:export,  fnName))
    end
    return esc(ret)
end

abstract Enum
macro GenEnums(list)
    tmp = list.args
    enumName = tmp[2]
    splice!(tmp, 1:2)
    enumType    = typeof(eval(tmp[4].args[1].args[2]))
    enumdict1   = Dict{enumType, Symbol}()
    for elem in tmp
        if elem.head == :const
            enumdict1[eval(elem.args[1].args[2])] = elem.args[1].args[1]
        end
    end
    dictname = gensym()
    enumtype =  quote
        immutable $(enumName){Sym, T} <: Enum
            number::T
            name::Symbol
        end
        $(dictname) = $enumdict1
        function $(enumName){T}(number::T)
            if !haskey($(dictname), number)
                error("x is not a GLenum")
            end
            $(enumName){$(dictname)[number], T}(number, $(dictname)[number])
        end

    end
    esc(Expr(:block, enumtype, tmp..., Expr(:export, :($(enumName)))))
end
include("glTypes.jl")
include("glFunctions.jl")
include("glConstants.jl")

end # module
