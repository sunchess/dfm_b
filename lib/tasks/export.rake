# encoding: utf-8
task :export => :environment do
  
  require 'csv'
  file_name = "dish_reviews_new.csv"
  
  i = 0
  CSV.open(file_name, "w") do |csv|
    csv << ["Review id; Restaurant id; Restaurant; Dish id; Dish"]
    Review.all.each do |r|
      puts i += 1
      csv << ["#{r.id};#{r.restaurant.id};#{r.restaurant.name};#{r.dish.id};#{r.dish.name}"]
    end
  end
  
  text = File.read(file_name)
  replace = text.gsub('"', '')
  File.open(file_name, "w") {|file| file.puts replace}
  
  %x{iconv -t cp1251 #{file_name}  > #{'c_'+file_name}}
  
end