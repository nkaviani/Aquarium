require 'aquarium/utils/array_utils'

module Aquarium
  module Aspects
    # Some classes and modules support a :default_object flag and use it if no type or
    # object is specified. For "convenience", requires that classes and modules including
    # this module have a hash @specification defined with keys :default_object, :types,
    # and :objects.
    module DefaultObjectHandler
      include Aquarium::Utils::ArrayUtils
      
      def default_objects_given
        if @default_objects.nil?
          ary1 = make_array(@specification[:default_objects])
          ary2 = make_array(@specification[:default_object])
          @default_objects = ary1 + ary2
        end
        @default_objects
      end

      def default_objects_given?
        not default_objects_given.empty?
      end
      
      def use_default_object_if_defined
        return unless default_objects_given?
        default_objects_given.each do |object|
          if (object.kind_of?(Class) || object.kind_of?(Module))
            @specification[:types] ||= []
            @specification[:types] << default_objects_given
          else
            @specification[:objects] ||= []
            @specification[:objects] << default_objects_given
          end
        end
      end
    end
  end
end
