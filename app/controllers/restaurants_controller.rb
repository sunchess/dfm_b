class RestaurantsController < ApplicationController
  def index
    @restaurants = Restaurant.all
  end
  
  def show
    if @restaurant = Restaurant.find_by_id(params[:id])
          
      @r_categories = RestaurantCategory.where("id IN (#{@restaurant.restaurant_categories})").collect { |c| c.name}.join(', ')
  
      @bill = []
      @restaurant.bill.to_i.times do
        @bill.push('$')
      end
      @bill = @bill.join('')
      
      @fb_obj = @restaurant
            
      @best_dishes = Dish.select([:id, :photo, :name]).where("network_id = ? AND rating > 0", @restaurant.network_id).limit(18).order("rating/votes DESC")
      @dishes_wimg = Dish.select([:id, :photo, :name]).where("network_id = ? AND photo IS NOT NULL", @restaurant.network_id).limit(18).order("rating/votes DESC") unless @best_dishes.nil?
      @any_dishes = Dish.select([:id, :photo, :name]).where("network_id = ?", @restaurant.network_id).limit(18).order("rating/votes DESC") unless @dishes_wimg.nil?

      
      @markers = []
      @restaurant.network.restaurants.select([:name, :lat, :lon]).each { |r| @markers.push("['#{r.name}', #{r.lat}, #{r.lon}, 1]")}
      @markers = "[#{@markers.join(',')}]"
      
      web = "http://dish.fm"
      url = "#{web}/restaurants/#{@restaurant.id}"
      
      @restaurant_img = @restaurant.restaurant_images.first.photo.iphone.url
      img = "#{web}#{@restaurant_img}" unless @restaurant_img.blank?
      
      @share_data = {
        :pinit => {
          :url => url,
          :media => img,
          :description => "#{@restaurant.description}"[0 .. 250]
        },
        :facebook => {
          :url => url
        },
        :twitter => {
          :description => "#{@restaurant.description}"[0 .. 100]
        }
      }
      
    end
  end
  
end
