class ProductSerializer < ApplicationSerializer
  attribute :type, if: :type?
  attributes :id, :name, :description, :reviews_count
  has_many :companies, serializer: AssociateCompanySerializer

  def type
    "Product"
  end

  def type?
    if instance_options[:has_type]
      false
    elsif instance_options[:has_type].nil?
      true
    end
  end
end
