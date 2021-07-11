module Benzene

import JSON

struct ComputationNode
    identifier::Symbol
    expression::Union{Symbol,Expr,Nothing}
    inputs::Set{Symbol}
    nodetype::Symbol
end

struct ComputationGraph
    nodes::Dict{Symbol,ComputationNode}
    ast::Expr
end

function nodefromparsedjson(parsed::Dict)::Pair{Symbol,ComputationNode}
    identifier = Meta.parse(parsed["title"])
    if typeof(identifier) != Symbol
        error(">" + parsed["title"] + "< does not parse to a symbol.")
    end
    expression = Meta.parse(parsed["properties"]["f"])
    inputs = Set{Symbol}()
    for inputobj in parsed["inputs"]
        if inputobj["name"] != "New input"
            input = Meta.parse(inputobj["name"])
            if typeof(input) != Symbol
                error(">" + inputobj["name"] + "< does not parse to a symbol.")
            end
            push!(inputs,input)
        end
    end
    nodeType = Meta.parse(parsed["flags"]["type"])
    node = ComputationNode(identifier,expression,inputs,nodeType)
    return (identifier=>node)
end

function replacesymbolwithexpression!(target::Any,sym::Symbol,
        ex::Expr)::Any
    if typeof(target) == Expr
        for (i,arg) in enumerate(target.args)
            if typeof(arg) == Symbol
                if arg == sym
                    target.args[i] = ex
                end 
            else
                replacesymbolwithexpression!(arg,sym,ex)
            end
        end
    end
end

function buildfunctionfromnodes(nodes::Dict{Symbol,ComputationNode},
        name::String)::Expr
    nameparsed = Meta.parse(name)
    if typeof(nameparsed) != Symbol
        error(">" + name + "< cannot be parsed as a symbol.")
    end
    expr = :(function $nameparsed(inputs...) 
        computedvalues = Dict{Symbol,Any}(inputs) 
    end)

    determinatedvalues = Set( [ identifier for (identifier,node) in 
                filter(x->x.second.nodetype==:input,nodes)])
    while !(length(determinatedvalues) == length(nodes))
        for (identifier, node) in nodes
            if !(identifier in determinatedvalues)
                if reduce(&,[input in determinatedvalues 
                    for input in node.inputs])
                    expression = node.expression
                    for input in node.inputs
                        replacesymbolwithexpression!(expression,
                            input, :(computedvalues[$(Meta.quot(input))]))
                    end
                    finalexpression = :(
                        computedvalues[$(Meta.quot(identifier))]=$expression)
                    push!(expr.args[2].args,finalexpression)
                    push!(determinatedvalues,identifier)
                end
            end
        end
    end
    push!(expr.args[2].args,:(return computedvalues))
    return expr
end

function graphfromjsonfile(path::String)::ComputationGraph 
    json = open(path,"r") do f
        read(f,String)
    end
    name = replace(path,".json"=>"")
    object = JSON.parse(json)
    nodes = Dict([ nodefromparsedjson(node) for node in object["nodes"] ]...)
    ast = buildfunctionfromnodes(nodes,name)
    return ComputationGraph(nodes,ast)
end

macro loadgraph(path)
    graph = graphfromjsonfile(path)
    return esc(graph.ast)
end

export @loadgraph

end