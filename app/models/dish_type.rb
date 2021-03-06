class DishType < ActiveRecord::Base
  
  has_many :dishes
  has_many :home_cooks
  has_many :dish_deliveries
  has_many :dish_subtypes
  
  mount_uploader :photo, ImageUploader
    
  def as_json(options={}) 
    super(:only => [:id, :name, :name_eng], :include => {:dish_subtypes => {:only => [:id, :name, :name_eng]}})
  end
  
  def self.format_for_api(timestamp = nil)
    if timestamp.nil? || (timestamp && DishType.where("updated_at >= ?", timestamp).any?)
      dtss = DishType.where("id NOT IN(4,6,7,14,16,19,25)")
    end
    
    if dtss && dtss.any?
      
      dish_types = [:type => {
        :photo => DishType.find_by_id(16).photo.url,
        :title => 'Starter',
        :subtypes => [
          {
            :title => 'Salad',
            :type_id => 16,
            :subtype_id => 0
          },
          {
            :title => 'Appetizer',
            :type_id => 14,
            :subtype_id => 0
          },
          {
            :title => 'Soup',
            :type_id => 4,
            :subtype_id => 0
          }
        ]
      }]
      
      dtss.order('`order`').each do |dt|
      
        dish_st = []
        dt.dish_subtypes.each do |dst|
          dish_st.push(
            :title => dst.name_eng,
            :type_id => dt.id,
            :subtype_id => dst.id
          )
        end
      
        dish_types.push(
          :type => {
            :photo => dt.photo.url,
            :title => dt.name_eng,
            :subtypes => dish_st
          }
        )
      end
    
      dish_types.push(:type => {
        :photo => DishType.find_by_id(25).photo.url,
        :title => 'Other',
        :subtypes => [
          {
            :title => 'Breakfast',
            :type_id => 6,
            :subtype_id => 0
          },
          {
            :title => 'Business lunch',
            :type_id => 7,
            :subtype_id => 0
          },
          {
            :title => 'Hookah',
            :type_id => 19,
            :subtype_id => 0
          }
        ]
      })
    else
      []
    end
  end
  
end
