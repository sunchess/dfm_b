class DishesController < ApplicationController
  def index
    per_page = 24
    @page = params[:page].to_i
    @review = Review.new
    @k = @page == 0 ? 0 : (@page - 1) * per_page
    
    if params[:search] && params[:search][:find]
      @dishes = Dish.where("LOWER(name) REGEXP '[[:<:]]#{params[:search][:find].downcase}'").order('rating DESC, votes DESC, photo DESC').page(@page).per(per_page)
      @search = params[:search][:find]
    else
      @dishes = Dish.order('rating DESC, photo DESC').page(@page).per(per_page)
    end
    
    unless @dishes.blank?
      @markers = Array.new
      @dishes.first.network.restaurants.take(10).each do |restaurant|
        @markers.push("['#{restaurant.name}', #{restaurant.lat}, #{restaurant.lon}, 1]")
      end
      @markers = '['+@markers.join(',')+']'
    end
    
  end
  
  def show
    @dish = Dish.find_by_id(params[:id])
  end
  
  def delete
    if dish = Dish.find_by_id(params[:id])
      dish.review.each do |r|
        r.restaurant.rating = r.restaurant.votes == 1?0 : (r.restaurant.rating * r.restaurant.votes - r.rating) / (r.restaurant.votes - 1)
        r.restaurant.votes = 1?0 : r.restaurant.votes - 1
        r.restaurant.save
        
        r.network.rating = r.network.votes == 1?0 : (r.network.rating * r.network.votes - r.rating) / (r.network.votes - 1)
        r.network.votes = 1?0 : r.network.votes - 1
        r.network.save
      end
      
      status = 'Cleared' if dish.destroy
      return render :json => status ||= 'SWR :`('
    else
      return render :json => 'Dish not found or already deleted.'
    end
  end
    
end
