class DishCategory < ActiveRecord::Base
  has_many :dishes
  has_many :dish_deliveries, :foreign_key => :dish_id
  
  def self.get_id(name)
    unless category = find_by_name(name)
      category = create(:name => name)
    end
    category.id
  end
  
end
