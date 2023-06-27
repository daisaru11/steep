module Steep
  module AST
    module Types
      class Factory
        attr_reader :definition_builder

        attr_reader :type_cache

        def inspect
          s = "#<%s:%#018x " % [self.class, object_id]
          s << "@definition_builder=#<%s:%#018x>" % [definition_builder.class, definition_builder.object_id]
          s + ">"
        end

        def initialize(builder:)
          @definition_builder = builder

          @type_cache = {}
          @method_type_cache = {}
          @method_type_cache.compare_by_identity
        end

        def type_name_resolver
          @type_name_resolver ||= RBS::Resolver::TypeNameResolver.new(definition_builder.env)
        end

        def type_opt(type)
          if type
            type(type)
          end
        end

        def type_1_opt(type)
          if type
            type_1(type)
          end
        end

        def type(type)
          unless type.location
            if ty = type_cache[type]
              return ty
            end
          end

          type_cache[type] =
            case type
            when RBS::Types::Bases::Any
              Any.new(location: type.location)
            when RBS::Types::Bases::Class
              Class.new(location: type.location)
            when RBS::Types::Bases::Instance
              Instance.new(location: type.location)
            when RBS::Types::Bases::Self
              Self.new(location: type.location)
            when RBS::Types::Bases::Top
              Top.new(location: type.location)
            when RBS::Types::Bases::Bottom
              Bot.new(location: type.location)
            when RBS::Types::Bases::Bool
              Boolean.new(location: type.location)
            when RBS::Types::Bases::Void
              Void.new(location: type.location)
            when RBS::Types::Bases::Nil
              Nil.new(location: type.location)
            when RBS::Types::Variable
              Var.new(name: type.name, location: type.location)
            when RBS::Types::ClassSingleton
              type_name = type.name
              Name::Singleton.new(name: type_name, location: type.location)
            when RBS::Types::ClassInstance
              type_name = type.name
              args = type.args.map {|arg| type(arg) }
              Name::Instance.new(name: type_name, args: args, location: type.location)
            when RBS::Types::Interface
              type_name = type.name
              args = type.args.map {|arg| type(arg) }
              Name::Interface.new(name: type_name, args: args, location: type.location)
            when RBS::Types::Alias
              type_name = type.name
              args = type.args.map {|arg| type(arg) }
              Name::Alias.new(name: type_name, args: args, location: type.location)
            when RBS::Types::Union
              Union.build(types: type.types.map {|ty| type(ty) }, location: type.location)
            when RBS::Types::Intersection
              Intersection.build(types: type.types.map {|ty| type(ty) }, location: type.location)
            when RBS::Types::Optional
              Union.build(types: [type(type.type), Nil.new(location: nil)], location: type.location)
            when RBS::Types::Literal
              Literal.new(value: type.literal, location: type.location)
            when RBS::Types::Tuple
              Tuple.new(types: type.types.map {|ty| type(ty) }, location: type.location)
            when RBS::Types::Record
              elements = type.fields.each.with_object({}) do |(key, value), hash|
                hash[key] = type(value)
              end
              Record.new(elements: elements, location: type.location)
            when RBS::Types::Proc
              func = Interface::Function.new(
                params: params(type.type),
                return_type: type(type.type.return_type),
                location: type.location
              )
              block = if type.block
                        Interface::Block.new(
                          type: Interface::Function.new(
                            params: params(type.block.type),
                            return_type: type(type.block.type.return_type),
                            location: type.location
                          ),
                          optional: !type.block.required,
                          self_type: type_opt(type.block.self_type)
                        )
                      end

              Proc.new(
                type: func,
                block: block,
                self_type: type_opt(type.self_type)
              )
            else
              raise "Unexpected type given: #{type}"
            end
        end

        def type_1(type)
          case type
          when Any
            RBS::Types::Bases::Any.new(location: type.location)
          when Class
            RBS::Types::Bases::Class.new(location: type.location)
          when Instance
            RBS::Types::Bases::Instance.new(location: type.location)
          when Self
            RBS::Types::Bases::Self.new(location: type.location)
          when Top
            RBS::Types::Bases::Top.new(location: type.location)
          when Bot
            RBS::Types::Bases::Bottom.new(location: type.location)
          when Boolean
            RBS::Types::Bases::Bool.new(location: type.location)
          when Void
            RBS::Types::Bases::Void.new(location: type.location)
          when Nil
            RBS::Types::Bases::Nil.new(location: type.location)
          when Var
            RBS::Types::Variable.new(name: type.name, location: type.location)
          when Name::Singleton
            RBS::Types::ClassSingleton.new(name: type.name, location: type.location)
          when Name::Instance
            RBS::Types::ClassInstance.new(
              name: type.name,
              args: type.args.map {|arg| type_1(arg) },
              location: type.location
            )
          when Name::Interface
            RBS::Types::Interface.new(
              name: type.name,
              args: type.args.map {|arg| type_1(arg) },
              location: type.location
            )
          when Name::Alias
            RBS::Types::Alias.new(
              name: type.name,
              args: type.args.map {|arg| type_1(arg) },
              location: type.location
            )
          when Union
            RBS::Types::Union.new(
              types: type.types.map {|ty| type_1(ty) },
              location: type.location
            )
          when Intersection
            RBS::Types::Intersection.new(
              types: type.types.map {|ty| type_1(ty) },
              location: type.location
            )
          when Literal
            RBS::Types::Literal.new(literal: type.value, location: type.location)
          when Tuple
            RBS::Types::Tuple.new(
              types: type.types.map {|ty| type_1(ty) },
              location: type.location
            )
          when Record
            fields = type.elements.each.with_object({}) do |(key, value), hash|
              hash[key] = type_1(value)
            end
            RBS::Types::Record.new(fields: fields, location: type.location)
          when Proc
            block = if type.block
                      RBS::Types::Block.new(
                        type: function_1(type.block.type),
                        required: !type.block.optional?,
                        self_type: type_1_opt(type.block.self_type)
                      )
                    end
            RBS::Types::Proc.new(
              type: function_1(type.type),
              self_type: type_1_opt(type.self_type),
              block: block,
              location: type.location
            )
          when Logic::Base
            RBS::Types::Bases::Bool.new(location: type.location)
          else
            __skip__ = raise "Unexpected type given: #{type} (#{type.class})"
          end
        end

        def function_1(func)
          params = func.params
          return_type = func.return_type

          RBS::Types::Function.new(
            required_positionals: params.required.map {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            optional_positionals: params.optional.map {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            rest_positionals: params.rest&.yield_self {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            trailing_positionals: [],
            required_keywords: params.required_keywords.transform_values {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            optional_keywords: params.optional_keywords.transform_values {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            rest_keywords: params.rest_keywords&.yield_self {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            return_type: type_1(return_type)
          )
        end

        def params(type)
          Interface::Function::Params.build(
            required: type.required_positionals.map {|param| type(param.type) },
            optional: type.optional_positionals.map {|param| type(param.type) },
            rest: type.rest_positionals&.yield_self {|param| type(param.type) },
            required_keywords: type.required_keywords.transform_values {|param| type(param.type) },
            optional_keywords: type.optional_keywords.transform_values {|param| type(param.type) },
            rest_keywords: type.rest_keywords&.yield_self {|param| type(param.type) }
          )
        end

        def type_param(type_param)
          Interface::TypeParam.new(
            name: type_param.name,
            upper_bound: type_opt(type_param.upper_bound),
            variance: type_param.variance,
            unchecked: type_param.unchecked?
          )
        end

        def type_param_1(type_param)
          RBS::AST::TypeParam.new(
            name: type_param.name,
            variance: type_param.variance,
            upper_bound: type_param.upper_bound&.yield_self {|u|
              case u_ = type_1(u)
              when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface
                u_
              else
                raise "`#{u_}` cannot be type parameter upper bound"
              end
            },
            location: type_param.location
          ).unchecked!(type_param.unchecked)
        end

        def method_type(method_type, method_decls:)
          mt = @method_type_cache[method_type] ||=
            Interface::MethodType.new(
              type_params: method_type.type_params.map {|param| type_param(param) },
              type: Interface::Function.new(
                params: params(method_type.type),
                return_type: type(method_type.type.return_type),
                location: method_type.location
              ),
              block: method_type.block&.yield_self do |block|
                Interface::Block.new(
                  optional: !block.required,
                  type: Interface::Function.new(
                    params: params(block.type),
                    return_type: type(block.type.return_type),
                    location: nil
                  ),
                  self_type: type_opt(block.self_type)
                )
              end,
              method_decls: Set[]
            )

          mt.with(method_decls: method_decls)
        end

        def method_type_1(method_type)
          RBS::MethodType.new(
            type_params: method_type.type_params.map {|param| type_param_1(param) },
            type: function_1(method_type.type),
            block: method_type.block&.yield_self do |block|
              RBS::Types::Block.new(
                type: function_1(block.type),
                required: !block.optional,
                self_type: type_1_opt(block.self_type)
              )
            end,
            location: nil
          )
        end

        def unfold(type_name, args)
          type(
            definition_builder.expand_alias2(
              type_name,
              args.empty? ? [] : args.map {|t| type_1(t) }
            )
          )
        end

        def expand_alias(type)
          case type
          when AST::Types::Name::Alias
            unfold(type.name, type.args)
          else
            type
          end
        end

        def deep_expand_alias(type, recursive: Set.new)
          case type
          when AST::Types::Name::Alias
            unless recursive.member?(type.name)
              unfolded = expand_alias(type)
              deep_expand_alias(unfolded, recursive: recursive.union([type.name]))
            end
          when AST::Types::Union
            types = type.types.map {|ty| deep_expand_alias(ty, recursive: recursive) or return }
            AST::Types::Union.build(types: types, location: type.location)
          when AST::Types::Intersection
            types = type.types.map {|ty| deep_expand_alias(ty, recursive: recursive) or return }
            AST::Types::Intersection.build(types: types, location: type.location)
          else
            type
          end
        end

        def flatten_union(type, acc = [])
          case type
          when AST::Types::Union
            type.types.each {|ty| flatten_union(ty, acc) }
          else
            acc << type
          end

          acc
        end

        def unwrap_optional?(type)
          case type
          when AST::Types::Union
            falsy_types, truthy_types = type.types.partition do |type|
              (type.is_a?(AST::Types::Literal) && type.value == false) ||
                type.is_a?(AST::Types::Nil)
            end

            [
              truthy_types.empty? ? nil : AST::Types::Union.build(types: truthy_types),
              falsy_types.empty? ? nil : AST::Types::Union.build(types: falsy_types)
            ]
          when AST::Types::Name::Alias
            type_ = expand_alias(type)
            if type_ == type
              [type_, type_]
            else
              unwrap_optional?(type_)
            end
          when AST::Types::Boolean
            [type, type]
          else
            [type, nil]
          end
        end

        def unwrap_optional(type)
          truthy, falsy = unwrap_optional?(type)
          [
            truthy || AST::Types::Bot.new,
            falsy || AST::Types::Bot.new
          ]
        end

        def module_name?(type_name)
          env.module_entry(type_name) ? true : false
        end

        def class_name?(type_name)
          env.class_entry(type_name) ? true : false
        end

        def env
          definition_builder.env
        end

        def absolute_type(type, context:)
          absolute_type = type_1(type).map_type_name do |name|
            absolute_type_name(name, context: context) || name.absolute!
          end
          type(absolute_type)
        end

        def absolute_type_name(type_name, context:)
          type_name_resolver.resolve(type_name, context: context)
        end

        def instance_type(type_name, args: nil, location: nil)
          raise unless type_name.class?

          definition = definition_builder.build_singleton(type_name)
          def_args = definition.type_params.map { Any.new(location: nil) }

          if args
            raise if def_args.size != args.size
          else
            args = def_args
          end

          AST::Types::Name::Instance.new(location: location, name: type_name, args: args)
        end

        def try_instance_type(type)
          case type
          when AST::Types::Name::Instance
            instance_type(type.name)
          when AST::Types::Name::Singleton
            instance_type(type.name)
          else
            nil
          end
        end

        def try_singleton_type(type)
          case type
          when AST::Types::Name::Instance, AST::Types::Name::Singleton
            AST::Types::Name::Singleton.new(name:type.name)
          else
            nil
          end
        end

        def normalize_type(type)
          case type
          when AST::Types::Name::Instance
            AST::Types::Name::Instance.new(
              name: env.normalize_module_name(type.name),
              args: type.args.map {|ty| normalize_type(ty) },
              location: type.location
            )
          when AST::Types::Name::Singleton
            AST::Types::Name::Singleton.new(
              name: env.normalize_module_name(type.name),
              location: type.location
            )
          when AST::Types::Any, AST::Types::Boolean, AST::Types::Bot, AST::Types::Nil,
            AST::Types::Top, AST::Types::Void, AST::Types::Literal, AST::Types::Class, AST::Types::Instance,
            AST::Types::Self, AST::Types::Var, AST::Types::Logic::Base
            type
          when AST::Types::Intersection
            AST::Types::Intersection.build(
              types: type.types.map {|type| normalize_type(type) },
              location: type.location
            )
          when AST::Types::Union
            AST::Types::Union.build(
              types: type.types.map {|type| normalize_type(type) },
              location: type.location
            )
          when AST::Types::Record
            AST::Types::Record.new(
              elements: type.elements.transform_values {|type| normalize_type(type) },
              location: type.location
            )
          when AST::Types::Tuple
            AST::Types::Tuple.new(
              types: type.types.map {|type| normalize_type(type) },
              location: type.location
            )
          when AST::Types::Proc
            type.map_type {|type| normalize_type(type) }
          when AST::Types::Name::Alias
            AST::Types::Name::Alias.new(
              name: type.name,
              args: type.args.map {|ty| normalize_type(ty) },
              location: type.location
            )
          when AST::Types::Name::Interface
            AST::Types::Name::Interface.new(
              name: type.name,
              args: type.args.map {|ty| normalize_type(ty) },
              location: type.location
            )
          end
        end
      end
    end
  end
end
