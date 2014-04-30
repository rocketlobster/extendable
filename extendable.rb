module Extendable

  def self.included base
    base.extend ClassMethods
    base.class_eval do
    end
  end

  module ClassMethods

    private

    def hashable_field attribute_name
      short_attribute = attribute_name.to_s.split('_value').first.to_sym
      validate :"validate_hashable_#{ short_attribute }"
      class_eval do

        define_method :"#{ short_attribute }" do
          return Hashie::Mash.new({}) unless send(attribute_name)
          Hashie::Mash.new JSON.parse(send(attribute_name))
        end

        define_method :"validate_hashable_#{ short_attribute }" do
          begin
            JSON.parse send(attribute_name) if send(attribute_name)
          rescue JSON::ParserError
            errors.add :base, 'Bad format of options'
          end
        end

      end
    end

    def sluggable attribute, options = {}
      validates attribute, uniqueness: true
      elements = options[:elements]
      min_length = options[:min_length]
      min_length ||= 3
      elements ||= (0..9).to_a
      after_create do
        return unless send(attribute).blank?
        slug = "" << options[:prefix].to_s
        slug << send(options[:dynamic_prefix]) if options[:dynamic_prefix]
        while self.class.where(attribute => slug).first or slug.length <= min_length
          slug << elements.sample.to_s
        end
        slug.upcase!
        update_attribute attribute, slug
      end
    end

    def indexable attribute
      @indexable_resource = attribute
      def [] value
        where(@indexable_resource => value).first
      end
    end

    def copyable options
      if (options[:only] && options[:except]) or (!options[:only] && !options[:except])
        raise ArgumentError
      end
      if options[:only]
        copyable_fields = options[:only]
      elsif options[:except] && connection.table_exists?(table_name)
        copyable_fields = columns.map{|c| c.name.to_sym} - options[:except] - [:id, :created_at, :updated_at]
      else
        copyable_fields = []
      end
      class_eval do
        define_copyable copyable_fields, options[:include].to_a
      end
    end

    def define_copyable copyable_fields, copyable_associations
      define_method(:copy) do |&block|
        new_resource = self.class.new
        copyable_fields.each do |field|
          new_resource.send("#{field}=", send(field))
        end
        copyable_associations.each do |associate|
          if send(associate).respond_to? :copy
            new_resource.send("#{associate}=", send(associate).copy)
          elsif send(associate)
            new_associate = send(associate).dup
            new_associate.save(validate: false)
            new_resource.send("#{associate}=", new_associate)
            new_associate.save(validate: false)
          end
        end
        block.call(new_resource) if block
        new_resource.save(validate: false)
        new_resource
      end
    end

  end
end
