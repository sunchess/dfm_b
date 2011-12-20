class DishType < ActiveRecord::Base
  has_many :dishes
  has_many :dish_subtypes
  
  def as_json(options={}) 
    super(:only => [:id, :name, :name_eng], :include => {:dish_subtypes => {:only => [:id, :name, :name_eng]}})
  end
end
