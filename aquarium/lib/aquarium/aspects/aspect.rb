require 'aquarium/extensions'
require 'aquarium/utils'
require 'aquarium/aspects/advice'
require 'aquarium/aspects/exclusion_handler'
require 'aquarium/aspects/join_point'
require 'aquarium/aspects/pointcut'
require 'aquarium/aspects/pointcut_composition'
require 'aquarium/aspects/default_object_handler'

module Aquarium
  module Aspects
    
    # == Aspect
    # Aspects "advise" one or more method invocations for one or more types or objects
    # (including class methods on types). The corresponding advice is a Proc that is
    # invoked either before the join point, after it returns, after it raises an exception, 
    # after either event, or around the join point, meaning the advice runs and it decides 
    # when and if to invoke the advised method. (Hence, around advice can run code before 
    # and after the join point call and it can "veto" the actual join point call).
    #  
    # See also Aquarium::Aspects::DSL::AspectDsl for more information.
    class Aspect
      include Advice
      include ExclusionHandler
      include DefaultObjectHandler
      include Aquarium::Utils::ArrayUtils
      include Aquarium::Utils::HashUtils
      include Aquarium::Utils::HtmlEscaper
  
      attr_accessor :verbose, :log
      attr_reader   :specification, :pointcuts, :advice
  
      ALLOWED_OPTIONS_SINGULAR = %w[advice type object method attribute method_option attribute_option pointcut default_object
       exclude_type exclude_object exclude_pointcut exclude_join_point exclude_method exclude_attribute noop].map {|o| o.intern}
  
      ALLOWED_OPTIONS_PLURAL = ALLOWED_OPTIONS_SINGULAR.map {|o| "#{o}s".intern}

      ALLOWED_OPTIONS = ALLOWED_OPTIONS_SINGULAR + ALLOWED_OPTIONS_PLURAL

      ADVICE_OPTIONS_SYNONYMS_MAP = {
        :call               => :advice,
        :invoke             => :advice,
        :advise_with        => :advice
      }
      
      ALLOWED_OPTIONS_SYNONYMS_MAP = { 
        :type               => :types,
        :within_type        => :types, 
        :within_types       => :types,
        :object             => :objects,
        :within_object      => :objects, 
        :within_objects     => :objects,
        :method             => :methods,
        :within_method      => :methods, 
        :within_methods     => :methods,
        :attribute          => :attributes,
        :pointcut           => :pointcuts,
        :within_pointcut    => :pointcuts,
        :within_pointcuts   => :pointcuts,
        :exclude_type       => :exclude_types,
        :exclude_object     => :exclude_objects,
        :exclude_pointcut   => :exclude_pointcuts,
        :exclude_join_point => :exclude_join_points,
        :exclude_method     => :exclude_methods,
        :exclude_attribute  => :exclude_attributes,
      }

      # Aspect.new (:around | :before | :after | :after_returning | :after_raising ) \
      #   (:pointcuts => [...]), | \
      #    ((:types => [...] | :objects => [...]), 
      #     :methods => [], :method_options => [...], \
      #     :attributes => [...], :attribute_options[...]), \
      #    (:advice = advice | do |join_point, obj, *args| ...; end)
      # 
      # where the parameters often have many synonyms (mostly to support a "humane
      # interface") and they are interpreted as followed:
      #
      # <tt>:around</tt>::
      #   Invoke the specified advice "around" the join points. It is up to the advice
      #   itself to call <tt>join_point.proceed</tt> (where <tt>join_point</tt> is the
      #   first argument passed to the advice) if it wants the advised method to actually
      #   execute.
      #
      # <tt>:before</tt>::
      #   Invoke the specified advice as before the join point.
      #
      # <tt>:after</tt>::
      #   Invoke the specified advice as after the join point either returns successfully
      #   or raises an exception.
      #
      # <tt>:after_returning</tt>::
      #   Invoke the specified advice as after the join point returns successfully.
      #
      # <tt>:after_raising</tt>::
      #   Invoke the specified advice as after the join point raises an exception.
      #
      # <tt>:pointcuts => pointcut || [pointcut_list]</tt>::
      # <tt>:pointcut  => pointcut || [pointcut_list]</tt>::
      # <tt>:within_pointcut  => pointcut || [pointcut_list]</tt>::
      # <tt>:within_pointcuts => pointcut || [pointcut_list]</tt>::
      #   One or an array of Pointcut or JoinPoint objects. Mutually-exclusive with the :types, :objects,
      #   :methods, :attributes, :method_options, and :attribute_options parameters.
      #
      # <tt>:types => type || [type_list]</tt>::
      # <tt>:type  => type || [type_list]</tt>::
      # <tt>:within_type  => type || [type_list]</tt>::
      # <tt>:within_types => type || [type_list]</tt>::
      #   One or an array of types, type names and/or type regular expessions to advise. 
      #   All the :types, :objects, :methods, :attributes, :method_options, and :attribute_options
      #   are used to construct Pointcuts internally.
      #
      # <tt>:types_and_descendents => type || [type_list]</tt>::
      # <tt>:type_and_descendents  => type || [type_list]</tt>::
      # <tt>:types_and_ancestors   => type || [type_list]</tt>::
      # <tt>:type_and_ancestors    => type || [type_list]</tt>::
      # <tt>:within_types_and_descendents => type || [type_list]</tt>::
      # <tt>:within_type_and_descendents  => type || [type_list]</tt>::
      # <tt>:within_types_and_ancestors   => type || [type_list]</tt>::
      # <tt>:within_type_and_ancestors    => type || [type_list]</tt>::
      #   One or an array of types and either their descendents or ancestors. 
      #   If you want both the descendents _and_ ancestors, use both options.
      #
      # <tt>:objects => object || [object_list]</tt>::
      # <tt>:object  => object || [object_list]</tt>::
      # <tt>:within_object  => object || [object_list]</tt>::
      # <tt>:within_objects => object || [object_list]</tt>::
      #   One or an array of objects to advise. 
      #
      # <tt>:default_objects => object || [object_list]</tt>::
      # <tt>:default_object  => object || [object_list]</tt>::
      #   An "internal" flag used by the methods that AspectDSL adds to Object. When no object
      #   or type is specified, the value of :default_objects will be used, if defined. The
      #   AspectDSL methods set the value to self, so that the user doesn't have to in the 
      #   appropriate contexts, for convenience. This flag is subject to change, so don't 
      #   use it explicitly!
      #
      # <tt>:methods => method || [method_list]</tt>::
      # <tt>:method  => method || [method_list]</tt>::
      # <tt>:within_method  => method || [method_list]</tt>::
      # <tt>:within_methods => method || [method_list]</tt>::
      #   One or an array of methods, method names and/or method regular expessions to match. 
      #   Unless :attributes are specified, defaults to :all, which searches for all public
      #   instance methods with an implied :method_options => :exclude_ancestor_methods, unless
      #   :method_options provided explicitly.
      #
      # <tt>:method_options => [options]</tt>::
      #   One or more options supported by Aquarium::Finders::MethodFinder. Defaults to :exclude_ancestor_methods
      #
      # <tt>:attributes => attribute || [attribute_list]</tt>::
      # <tt>:attribute  => attribute || [attribute_list]</tt>::
      # <tt>:within_attribute  => attribute || [attribute_list]</tt>::
      # <tt>:within_attributes => attribute || [attribute_list]</tt>::
      #   One or an array of attribute names and/or regular expessions to match. 
      #   This is syntactic sugar for the corresponding attribute readers and/or writers
      #   methods, as specified using the <tt>:attrbute_options. Any matches will be
      #   joined with the matched :methods.</tt>.
      #
      # <tt>:attribute_options => [options]</tt>::
      #   One or more of <tt>:readers</tt>, <tt>:reader</tt> (synonymous), 
      #   <tt>:writers</tt>, and/or <tt>:writer</tt> (synonymous). By default, both
      #   readers and writers are matched.
      #
      # <tt>:exclude_pointcuts   => pc || [pc_list]</tt>::
      # <tt>:exclude_pointcut    => pc || [pc_list]</tt>::
      # <tt>:exclude_join_points => jp || [jp_list]</tt>::
      # <tt>:exclude_join_point  => jp || [jp_list]</tt>::
      # <tt>:exclude_types       => type || [type_list]</tt>::
      # <tt>:exclude_types       => type || [type_list]</tt>::
      # <tt>:exclude_type        => type || [type_list]</tt>::
      # <tt>:exclude_objects     => object || [object_list]</tt>::
      # <tt>:exclude_object      => object || [object_list]</tt>::
      # <tt>:exclude_methods     => method || [method_list]</tt>::
      # <tt>:exclude_method      => method || [method_list]</tt>::
      # <tt>:exclude_attributes  => attribute || [attribute_list]</tt>::
      # <tt>:exclude_attribute   => attribute || [attribute_list]</tt>::
      #   Exclude the specified "things" from the matched join points.
      #
      # <tt>:exclude_types_and_descendents => type || [type_list]</tt>::
      # <tt>:exclude_type_and_descendents  => type || [type_list]</tt>::
      # <tt>:exclude_types_and_ancestors   => type || [type_list]</tt>::
      # <tt>:exclude_type_and_ancestors    => type || [type_list]</tt>::
      #   Exclude the specified types and their descendents, ancestors.
      #   If you want to exclude both the descendents _and_ ancestors, use both options.
      #
      # The actual advice to execute is the block or you can pass a Proc using :advice => proc.
      # Note that the advice takes a join_point argument, which will include a non-nil 
      # JoinPoint#Context object, the object being executed, and the argument list to the method.
      def initialize *options, &block
        process_input options, &block
        init_pointcuts
        return if specification[:noop]
        advise_join_points
      end
  
      def join_points_matched 
        get_jps :join_points_matched
      end
  
      def join_points_not_matched
        get_jps :join_points_not_matched
      end
      
      def unadvise
        return if @specification[:noop]
        @pointcuts.each do |pointcut|
          interesting_join_points(pointcut).each do |join_point|
            remove_advice_for_aspect_at join_point
          end
        end
      end

      alias :unadvise_join_points :unadvise
  
      def inspect
        "Aspect: {specification: #{specification.inspect}, pointcuts: #{pointcuts.inspect}, advice: #{advice.inspect}}"
      end
  
      alias :to_s :inspect
  
      # We have to ignore advice in the comparison. As recently discussed in ruby-users, there are very few situations.
      # where Proc#eql? returns true.
      def eql? other
        self.object_id == other.object_id ||
          (self.class.eql?(other.class) && specification == other.specification && pointcuts == other.pointcuts)
      end

      alias :== :eql?
  
      protected

      def process_input options, &block
        @original_options = options.flatten
        make_specification options, &block
        @verbose = @specification[:verbose] || false
        @log     = @specification[:log] || ""
      end  
  
      def make_specification options, &block
        opts = rationalize_parameters options.flatten.dup
        # For non-hash inputs, use an empty string for the value
        @specification = Aquarium::Utils::MethodUtils.method_args_to_hash(*opts) {|option| ""} 
        use_default_object_if_defined unless (types_given? || objects_given? || pointcuts_given?)
        use_first_nonadvice_symbol_as_method(opts) unless methods_given?
        @specification[:exclude_types_calculated] = @specification[:exclude_types]
        @advice = determine_advice block
        validate_specification
      end

      def determine_advice block
        # There can be only one advice; take the last one...
        block || (@specification[:advice].kind_of?(Array) ? @specification[:advice].last : @specification[:advice])
      end
      
      def init_pointcuts
        pointcuts = []
        if pointcuts_given?
          pointcuts_given.each do |pointcut|
            if pointcut.kind_of?(Aquarium::Aspects::Pointcut)
              pointcuts << pointcut 
            elsif pointcut.kind_of?(Aquarium::Aspects::JoinPoint)
              pointcuts << Aquarium::Aspects::Pointcut.new(:join_point => pointcut) 
            else  # a hash of Pointcut.new options?
              pointcuts << Aquarium::Aspects::Pointcut.new(pointcut) 
            end
          end
        else
          pc_options = {}
          ALLOWED_OPTIONS_PLURAL.each do |option|
            next if pointcut_new_doesnt_accept? option
            self.instance_eval(<<-EOF, __FILE__, __LINE__)
              pc_options[:#{option}] = #{option}_given if #{option}_given?
            EOF
          end
          pointcuts << Aquarium::Aspects::Pointcut.new(pc_options)
        end
        @pointcuts = Set.new(remove_excluded_join_points_and_empty_pointcuts(pointcuts))
      end

      def pointcut_new_doesnt_accept? option
        case option
        when :advices:         true   
        when :pointcuts:       true
        when :default_objects: true
        when :noops:           true
        else                   false
        end
      end
      
      def remove_excluded_join_points_and_empty_pointcuts pointcuts
        pointcuts.reject do |pc|
          pc.join_points_matched.delete_if do |jp|
            join_point_excluded? jp
          end
          pc.empty?
        end
      end
      
      def advise_join_points
        advice = @advice.to_proc
        @pointcuts.each do |pointcut|
          interesting_join_points(pointcut).each do |join_point|
            attr_name = Aspect.make_advice_chain_attr_sym(join_point)
            add_advice_framework(join_point) if need_advice_framework?(join_point)
            Aquarium::Aspects::Advice.sort_by_priority_order(specified_advice_kinds).reverse.each do |advice_kind|
              add_advice_to_chain join_point, advice_kind, advice
            end
          end
        end
      end
  
      def interesting_join_points pointcut
        pointcut.join_points_matched.reject do |join_point| 
          join_point_for_aspect_implementation_method? join_point
        end
      end

      def join_point_for_aspect_implementation_method? join_point
        join_point.method_name.to_s.index("#{Aspect.aspect_method_prefix}") == 0
      end
      
      def add_advice_to_chain join_point, advice_kind, advice
        start_of_advice_chain = Aspect.get_advice_chain join_point
        options = @specification.merge({
          :aspect => self,
          :advice_kind => advice_kind, 
          :advice => advice, 
          :next_node => start_of_advice_chain,
          :static_join_point => join_point})
        # New node is new start of chain.
        Aspect.set_advice_chain(join_point, Aquarium::Aspects::AdviceChainNodeFactory.make_node(options))
      end

      def get_jps which_jps
        jps = Set.new
        @pointcuts.each do |pointcut|
          jps = jps.union(pointcut.send(which_jps))
        end
        jps
      end
  
      # Useful for debugging...
      def self.advice_chain_inspect advice_chain
        return "[nil]" if advice_chain.nil?
        "<br/>"+advice_chain.inspect do |ac|
          "#{ac.class.name}:#{ac.object_id}: join_point = #{ac.static_join_point}: aspect = #{ac.aspect.object_id}, next_node = #{advice_chain_inspect ac.next_node}"
        end.gsub(/\</,"&lt;").gsub(/\>/,"&gt;")+"<br/>"
      end

      def need_advice_framework? join_point
        alias_method_name = (Aspect.make_saved_method_name join_point).intern
        private_method_defined?(join_point, alias_method_name) == false
      end
      
      def add_advice_framework join_point
        alias_method_name = (Aspect.make_saved_method_name join_point).intern
        type_to_advise = Aspect.type_to_advise_for join_point
        # Note: Must set advice chain, a class variable on the type we're advising, FIRST. 
        # Otherwise the class_eval that follows will assume the @@ advice chain belongs to Aspect!
        Aspect.set_advice_chain join_point, Aquarium::Aspects::AdviceChainNodeFactory.make_node(
          :aspect => nil,  # Belongs to all aspects that might advise this join point!
          :advice_kind => :none, 
          :alias_method_name => alias_method_name,
          :static_join_point => join_point)
        type_being_advised_text = join_point.instance_method? ? "self.class" : "self"
        unless Aspect.is_type_join_point?(join_point) 
          type_being_advised_text = "(class << self; self; end)"
        end
        type_to_advise2 = join_point.instance_method? ? type_to_advise : (class << type_to_advise; self; end)
        type_to_advise2.class_eval(<<-EOF, __FILE__, __LINE__)
          #{def_eigenclass_method_text join_point}
          #{alias_original_method_text alias_method_name, join_point, type_being_advised_text}
        EOF
      end
      
      def static_method_prefix join_point
        if join_point.instance_method?
          "@@type_being_advised = self"
        else
          "@@type_being_advised = self"
          "class << self"
        end
      end

      def static_method_suffix join_point
        join_point.instance_method? ? "" : "end"
      end
      
      # When advising an instance, create an override method that gets advised instead of the types method.
      # Otherwise, all objects will be advised!
      # Note: this also solves bug #15202.
      def def_eigenclass_method_text join_point
        Aspect.is_type_join_point?(join_point) ? "" : "def #{join_point.method_name} *args; super; end"
      end

      # For the temporary eigenclass method wrapper, alias it to a temporary name then undefine it, so it 
      # completely disappears. Next, remove_method on the method name so the object starts responding again
      # to the original definition.
      def undef_eigenclass_method_text join_point
        Aspect.is_type_join_point?(join_point) ? "" : "remove_method :#{join_point.method_name}"
      end

      # TODO Move to JoinPoint
      def self.is_type_join_point? join_point
        Aquarium::Utils::TypeUtils.is_type? join_point.type_or_object
      end
      
      def self.type_to_advise_for join_point
        join_point.target_type ? join_point.target_type : (class << join_point.target_object; self; end)
      end

      def alias_original_method_text alias_method_name, join_point, type_being_advised_text
        target_self = join_point.instance_method? ? "self" : join_point.target_type.name
        advice_chain_attr_sym = Aspect.make_advice_chain_attr_sym join_point
        <<-EOF
        alias_method :#{alias_method_name}, :#{join_point.method_name}
        def #{join_point.method_name} *args, &block_for_method
          advice_chain = #{type_being_advised_text}.send :class_variable_get, "#{advice_chain_attr_sym}"
          static_join_point = advice_chain.static_join_point
          advice_join_point = static_join_point.make_current_context_join_point(
            :advice_kind => :before, 
            :advised_object => #{target_self}, 
            :parameters => args, 
            :block_for_method => block_for_method)
          advice_chain.call advice_join_point, #{target_self}, *args
        end
        #{join_point.visibility.to_s} :#{join_point.method_name}
        private :#{alias_method_name}
        EOF
      end

      def unalias_original_method_text alias_method_name, join_point
        <<-EOF
        alias_method :#{join_point.method_name}, :#{alias_method_name}
        #{join_point.visibility.to_s} :#{join_point.method_name}
        undef_method :#{alias_method_name}
        EOF
      end
  
      def remove_advice_for_aspect_at join_point
        prune_nodes_in_advice_chain_for join_point
        advice_chain = Aspect.get_advice_chain join_point
        remove_advice_framework_for(join_point) if advice_chain.empty?
      end

      def prune_nodes_in_advice_chain_for join_point
        advice_chain = Aspect.get_advice_chain join_point
        # Use equal? for the aspects to compare object id only,
        while advice_chain.empty? == false && advice_chain.aspect.equal?(self)
          advice_chain = advice_chain.next_node 
        end
        node = advice_chain
        while node.empty? == false
          while node.next_node.aspect.equal?(self)
            node.next_node = node.next_node.next_node
          end
          node = node.next_node 
        end
        Aspect.set_advice_chain join_point, advice_chain
      end
  
      def remove_advice_framework_for join_point
        type_to_advise = Aspect.type_to_advise_for join_point
        type_to_advise.class_eval(<<-EVAL_WRAPPER, __FILE__, __LINE__)
          #{restore_original_method_text join_point}
        EVAL_WRAPPER
        Aspect.remove_advice_chain join_point
      end
  
      def restore_original_method_text join_point
        alias_method_name = (Aspect.make_saved_method_name join_point).intern
        <<-EOF
          #{static_method_prefix join_point}
          #{unalias_original_method_text alias_method_name, join_point}
          #{undef_eigenclass_method_text join_point}
          #{static_method_suffix join_point}
        EOF
      end
      
      # TODO optimize calls to these *_advice_chain methods from other private methods.
      def self.set_advice_chain join_point, advice_chain
        advice_chain_attr_sym = self.make_advice_chain_attr_sym join_point
        type_to_advise_for(join_point).send :class_variable_set, advice_chain_attr_sym, advice_chain
      end

      def self.get_advice_chain join_point
        advice_chain_attr_sym = self.make_advice_chain_attr_sym join_point
        type_to_advise_for(join_point).send :class_variable_get, advice_chain_attr_sym
      end
    
      def self.remove_advice_chain join_point
        advice_chain_attr_sym = self.make_advice_chain_attr_sym join_point
        type_to_advise_for(join_point).send :remove_class_variable, advice_chain_attr_sym
      end

      def private_method_defined? join_point, alias_method_name
        type_to_advise = Aspect.type_to_advise_for join_point
        type_to_advise.send(:private_instance_methods).include? alias_method_name.to_s
      end
  
      def self.make_advice_chain_attr_sym join_point
        class_or_object_prefix = is_type_join_point?(join_point) ? "class_" : ""
        type_or_object_key = make_type_or_object_key join_point
        valid_name = Aquarium::Utils::NameUtils.make_valid_attr_name_from_method_name join_point.method_name
        "@@#{Aspect.aspect_method_prefix}#{class_or_object_prefix}advice_chain_#{type_or_object_key}_#{valid_name}".intern
      end
      
      def self.make_saved_method_name join_point
        type_or_object_key = make_type_or_object_key join_point
        valid_name = Aquarium::Utils::NameUtils.make_valid_attr_name_from_method_name join_point.method_name
        "#{Aspect.aspect_method_prefix}saved_#{type_or_object_key}_#{valid_name}"
      end
  
      def self.aspect_method_prefix
        "_aspect_"
      end
  
      def self.determine_type_or_object join_point
        join_point.type_or_object
        # type_or_object = join_point.type_or_object
        # method_type = join_point.instance_or_class_method
        # if is_type_join_point? join_point
        #   type_or_object = Aquarium::Utils::MethodUtils.definer type_or_object, join_point.method_name, "#{method_type}_method_only".intern
        # end
        # type_or_object
      end
      
      def self.make_type_or_object_key join_point
        Aquarium::Utils::NameUtils.make_type_or_object_key determine_type_or_object(join_point)
      end
      
      def specified_advice_kinds
        @specification.keys.select do |key|
          Aquarium::Aspects::Advice.kinds.include? key
        end
      end
  
      def rationalize_parameters opts
        return opts unless opts.last.kind_of?(Hash)
        hash = opts.pop.dup
        opts.push hash
        ALLOWED_OPTIONS_SYNONYMS_MAP.each do |syn, actual|
          if hash.has_key? syn
            hash[actual] = make_array(hash[actual], hash[syn])
            hash.delete syn
          end
        end
        # Only one advice argument allowed.
        unless hash.has_key?(:advice)
          ADVICE_OPTIONS_SYNONYMS_MAP.each do |syn, actual|
            if hash.has_key? syn
              hash[actual] = hash[syn]
              hash.delete syn
            end
          end
        end
        ALLOWED_OPTIONS_PLURAL.each do |opt|
          case opt
          when :advices:  next
          when :noops:    next
          end
          hash[opt] = Set.new(make_array(hash[opt]))
        end
        opts
      end
      
      def validate_specification 
        bad_options("One of #{Aquarium::Aspects::Advice.kinds.inspect} is required.") unless advice_kinds_given?
        bad_options(":around can't be used with :before.") if around_given_with? :before
        bad_options(":around can't be used with :after.")  if around_given_with? :after
        bad_options(":around can't be used with :after_returning.")  if around_given_with? :after_returning
        bad_options(":around can't be used with :after_raising.")    if around_given_with? :after_raising
        bad_options(":after can't be used with :after_returning.")   if after_given_with? :after_returning
        bad_options(":after can't be used with :after_raising.")     if after_given_with? :after_raising
        bad_options(":after_returning can't be used with :after_raising.") if after_returning_given_with? :after_raising
        unless pointcuts_given? or types_given? or objects_given? or default_objects_given?
          bad_options("At least one of :pointcut(s), :type(s), :object(s) is required.") 
        end
        if pointcuts_given? and (types_given? or objects_given?)
          bad_options("Can't specify both :pointcut(s) and one or more of :type(s), and/or :object(s).") 
        end
        @specification.each_key do |parameter|
          check_parameter parameter
        end
        if @advice.nil? && @specification[:noop].nil?
          bad_options "No advice block nor :advice argument was given."
        end
        if @advice.arity == -2
          bad_options "It appears that your advice parameter list is the obsolete format |jp, *args|. The correct format is |jp, object, *args|"
        end
      end

      def check_parameter parameter
        bad_options("Unrecognized parameter: :#{parameter}") unless is_valid_parameter(parameter)
      end
      
      def is_valid_parameter key
        ALLOWED_OPTIONS.include?(key) || ALLOWED_OPTIONS_SYNONYMS_MAP.keys.include?(key) || 
          ADVICE_OPTIONS_SYNONYMS_MAP.keys.include?(key) || KINDS_IN_PRIORITY_ORDER.include?(key) ||
          key == :exclude_types_calculated ||
          parameter_is_a_method_name?(key)    # i.e., use_first_nonadvice_symbol_as_method
      end
      
      def parameter_is_a_method_name? name
        @specification[:methods].include? name
      end
      
      def advice_kinds_given
        Aquarium::Aspects::Advice.kinds.inject([]) {|ary, kind| ary << @specification[kind] if @specification[kind]; ary}
      end

      def advice_kinds_given?
        not advice_kinds_given.empty?
      end

      %w[around after after_returning].each do |advice_kind|
        class_eval(<<-EOF, __FILE__, __LINE__)
          def #{advice_kind}_given_with? other_advice_kind_sym
            @specification[:#{advice_kind}] and @specification[other_advice_kind_sym]
          end
        EOF
      end
      
      ALLOWED_OPTIONS_PLURAL.each do |name|
        case name
        when :advices         : next
        when :default_objects : next
        when :noops           : next
        end
        class_eval(<<-EOF, __FILE__, __LINE__)
          def #{name}_given
            make_array(@specification[:#{name}])
          end
  
          def #{name}_given?
            not (#{name}_given.nil? or #{name}_given.empty?)
          end
        EOF
      end
      
      def use_first_nonadvice_symbol_as_method options
        2.times do |i|
          if options.size >= i+1
            sym = options[i]
            if sym.kind_of?(Symbol) && !Aquarium::Aspects::Advice::kinds.include?(sym)
              @specification[:methods] = Set.new([sym])
              return
            end
          end
        end
      end
      
      def bad_options message
        raise Aquarium::Utils::InvalidOptions.new("Invalid options given. " + message + 
        " (options: #{@original_options.inspect}, mapped to specification: #{@specification.inspect})")
      end
    end
  end
end
