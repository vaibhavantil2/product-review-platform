module SwaggerDocs::Aspect
  extend ActiveSupport::Concern

  included do
    include Swagger::Blocks

    # example :Aspect do
    #   key :aspect, ["Quality Tools & Materials", "Skillful & Knowledgeable"]
    # end

    swagger_schema :Aspect do
      key :type, :object
      key :required, [:id, :name, :description]

      property :id do
        key :type, :string
        key :example, "AbC123"
      end

      property :name do
        key :type, :string
        key :example, 'Reliability'
      end

      property :description do
        key :type, :string
        key :example, 'The ability to deliver the promised product or service in a consistent and accurate manner.'
      end
    end

    swagger_schema :Aspect_Company do
      key :type, :object
      property :aspect do
        key :type, :object
        key :'$ref', :Aspect
      end
      property :count do
        key :type, :number
        key :example, 30
      end
    end

    swagger_schema :AspectInput do
      allOf do
        schema do
          property :aspect do
            key :type, :object
            property :name do
              key :type, :string
            end
            property :description do
              key :type, :string
            end
          end
        end
      end
    end
  end
end
