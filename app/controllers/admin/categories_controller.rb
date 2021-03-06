class Admin::CategoriesController < ApplicationController

  before_filter :ensure_is_admin

  def index
    @selected_left_navi_link = "listing_categories"
    @categories = @current_community.top_level_categories.includes(:children)
  end

  def new
    @selected_left_navi_link = "listing_categories"
    @category = Category.new
    @default_transaction_types = Maybe(@current_community.categories.last).transaction_types.or_else { [] }
    shapes = ListingService::API::Api.shapes.get(community_id: @current_community.id)[:data]
    render locals: { shapes: shapes }
  end

  def create
    @selected_left_navi_link = "listing_categories"
    @category = Category.new(params[:category])
    @category.community = @current_community
    @category.parent_id = nil if params[:category][:parent_id].blank?
    @category.sort_priority = Admin::SortingService.next_sort_priority(@current_community.categories)
    logger.info "Translations #{@category.translations.inspect}"
    @default_transaction_types = Maybe(@current_community.categories.last).transaction_types.or_else { [] }
    if @category.save
      update_category_listing_shapes(params, @category)
      redirect_to admin_categories_path
    else
      flash[:error] = "Category saving failed"
      render :action => :new
    end
  end

  def edit
    @selected_left_navi_link = "listing_categories"
    @category = @current_community.categories.find_by_url_or_id(params[:id])
    @default_transaction_types = @category.transaction_types
    shapes = ListingService::API::Api.shapes.get(community_id: @current_community.id)[:data]
    render locals: { shapes: shapes }
  end

  def update
    @selected_left_navi_link = "listing_categories"
    @category = @current_community.categories.find_by_url_or_id(params[:id])
    @default_transaction_types = @category.transaction_types

    if @category.update_attributes(params[:category])
      update_category_listing_shapes(params, @category)
      redirect_to admin_categories_path
    else
      flash[:error] = "Category saving failed"
      render :action => :edit
    end
  end

  def order
    sort_priorities = params[:order].each_with_index.map do |category_id, index|
      [category_id, index]
    end.inject({}) do |hash, ids|
      category_id, sort_priority = ids
      hash.merge(category_id.to_i => sort_priority)
    end

    @current_community.categories.select do |category|
      sort_priorities.has_key?(category.id)
    end.each do |category|
      category.update_attributes(:sort_priority => sort_priorities[category.id])
    end

    render nothing: true, status: 200
  end

  # Remove form
  def remove
    @selected_left_navi_link = "listing_categories"
    @category = @current_community.categories.find_by_url_or_id(params[:id])
    @possible_merge_targets = Admin::CategoryService.merge_targets_for(@current_community.categories, @category)
  end

  # Remove action
  def destroy
    @category = @current_community.categories.find_by_url_or_id(params[:id])
    @category.destroy
    CategoryListingShape.delete_all(category_id: @category.id)
    redirect_to admin_categories_path
  end

  def destroy_and_move
    @category = @current_community.categories.find_by_url_or_id(params[:id])
    new_category = @current_community.categories.find_by_url_or_id(params[:new_category])

    if new_category
      # Move listings
      @category.own_and_subcategory_listings.update_all(:category_id => new_category.id)

      # Move custom fields
      Admin::CategoryService.move_custom_fields!(@category, new_category)
    end

    @category.destroy

    redirect_to admin_categories_path
  end

  private

  def update_category_listing_shapes(params, category)
    transaction_type_ids = params[:category][:transaction_type_attributes].map { |tt_param| tt_param[:transaction_type_id].to_i }

    shapes = ListingService::API::Api.shapes.get(community_id: @current_community.id)[:data]
    selected_shapes = shapes.select { |s| transaction_type_ids.include? s[:transaction_type_id] }

    raise ArgumentError.new("No shapes selected for category #{category.id}, transaction_type_ids: #{transaction_type_ids}") if selected_shapes.empty?

    CategoryListingShape.delete_all(category_id: category.id)

    selected_shapes.each { |s|
      CategoryListingShape.create!(category_id: category.id, listing_shape_id: s[:id])
    }
  end

end
