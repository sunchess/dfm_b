class API < ActiveRecord::Base
  
  def self.get_dish(user_id, dish_id)
    
    if dish = Dish.find_by_id(dish_id)
      user_review = Review.find_by_dish_id_and_user_id(dish.id,user_id) if user_id
      position_in_network = Dish.where("rating/votes >= ? AND network_id = ?", "#{dish.rating/dish.votes}", dish.network_id).order("rating/votes DESC, votes DESC").count if dish.votes != 0
      position_in_type = Dish.where("rating/votes >= ? AND dish_type_id = ?", "#{dish.rating/dish.votes}", dish.dish_type_id).order("rating/votes DESC, votes DESC").count if dish.votes != 0
      subtype = DishSubtype.find_by_id(dish.dish_subtype_id)
    
      top_expert_id = (Review.where('dish_id = ?', dish.id).group('user_id').count).max[0] if Review.find_by_dish_id(dish.id)
      if user = User.find_by_id(top_expert_id)
        top_expert = {
          :user_name => user.name,
          :user_avatar => "http://graph.facebook.com/#{user.facebook_id}/picture?type=square",
          :user_id => user.id
        }
      end
    
      reviews = []
      dish.reviews.each do |review|
        reviews.push({
          :image_sd => review.photo.iphone.url != '/images/noimage.jpg' ? review.photo.iphone.url : '' ,
          :image_hd => review.photo.iphone_retina.url != '/images/noimage.jpg' ? review.photo.iphone_retina.url : '',
          :user_id => review.user_id,
          :user_name => review.user.name,
          :user_avatar => "http://graph.facebook.com/#{review.user.facebook_id}/picture?type=square",
          :text => review.text,
          :rating => review.rating
        })
      end
    
      restaurants = []
      dish.network.restaurants.each do |restaurant|
        restaurants.push({
          :address => restaurant.address,
          :phone => restaurant.phone.to_s,
          :working_hours => restaurant.time,
          :lat => restaurant.lat,
          :lon => restaurant.lon,
          :description => restaurant.description.to_s
        })
      end
    
      data = {
        :name => dish.name,
        :current_user_rating => user_review ? user_review.rating : '',
        :photo => dish.find_image && dish.find_image.iphone.url != '/images/noimage.jpg' ? dish.find_image.iphone.url : '',
        :rating => dish.rating,
        :votes => dish.votes,
        :position_in_network => position_in_network,
        :dishes_in_network => dish.network.dishes.count,
        :position_in_type => position_in_type,
        :dishes_in_type => dish.dish_type.dishes.count,
        :type_name => dish.dish_type.name,
        :subtype_name => dish.dish_subtype ? dish.dish_subtype.name : '',
        :restaurant_name => dish.network.name, 
        :restaurant_id => dish.network.restaurants.first.id, 
        :description => dish.description.to_s,
        :reviews => reviews,
        :top_expert => top_expert ||= nil,
        :restaurants => restaurants,
        :error => {:description => nil, :code => nil}
      
      }
      data.as_json
    else
      {:error => {:description => 'Dish not found', :code => 666}}.as_json
    end
  end
  
end