class LikesController < ApplicationController
  include SwaggerDocs::Likes
  before_action -> { doorkeeper_authorize! :read_only, :read_write }, only: [:index, :show]
  before_action only: [:create, :destroy] do
    doorkeeper_authorize! :read_write, :write_only
  end

  before_action :set_likeable, only: [:index, :create]
  before_action :validate_likeable_presence, only: [:index, :create]

  before_action :set_like, only: [:show, :destroy]
  before_action :validate_like_pressence, only: [:show, :destroy]

  before_action :check_liker_params, only: [:create]
  before_action :set_new_like_liker, only: [:create]
  before_action :validate_liker_presence, only: [:create]

  after_action only: [:index] { set_pagination_header(@likeable.likes.kept) }

  # GET /reviews/:review_id/likes
  def index
    @likes = params[:page] == 'all' ? @likeable.likes.kept : @likeable.likes.kept.page(params[:page]).per(params[:per_page])
    render json: @likes
  end

  # GET /likes/1
  def show
    render json: @like
  end

  # POST /reviews/:review_id/likes
  def create
    if @likes.save
      render json: @likes, status: :created, location: @likes
    else
      render json: @likes.errors.messages, status: :unprocessable_entity
    end
  end

  # DELETE /likes/1
  def destroy
    @like.discard
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def change_params_key
      @whitelisted["liker_id"] = @whitelisted["from_id"]
      @whitelisted.delete("from_id")
      @whitelisted["liker_type"] = @whitelisted["from_type"].classify.safe_constantize
      @whitelisted.delete("from_type")
    end

    def set_likeable
      params.each do |name, value|
        if name =~ /(.+)_id$/
          @class = Regexp.last_match[1]
          @likeable_type = Regexp.last_match[1].classify.safe_constantize
          @likeable = @likeable_type.find_by_hashid(value) if !@likeable_type.nil?
        end
      end
    end

    def validate_likeable_presence
      render_error(404, "#{I18n.t('like.likeable', model: @likeable_type)}": [I18n.t('general_error.not_found')]) if @likeable.nil? || !@likeable.presence?
    end

    def set_like
      @like = Like.kept.find_by_hashid(params[:id])
    end

    def validate_like_pressence
      render_error(404, "#{I18n.t('like.key_id')}": [I18n.t('general_error.not_found')]) if @like.nil? || !@like.presence?
    end

    def set_new_like_liker
      type = params[:like][:from_type].classify.safe_constantize
      if !type.nil?
        if !(type < Liker)
          render_error(422, "#{I18n.t('general_error.from_type_key')}": [I18n.t('general_error.invalid')])
        else
          @liker = type.find_by_hashid(params[:like][:from_id])
          @whitelisted = create_params
          change_params_key
          convert_hashids
          @likes = Like.new(@whitelisted)
        end
      else
        render_error(422, "#{I18n.t('general_error.from_type_key')}": [I18n.t('general_error.invalid')])
      end
    end

    def check_liker_params
      if params[:like].present?
        if !(params[:like][:from_id].present? && params[:like][:from_type].present?)
          render_error(400, "#{I18n.t('general_error.params_missing_key')}": [I18n.t('general_error.params_missing_value', model: "from_id/from_type")])
        end
      else
        render_error(400, "#{I18n.t('general_error.params_missing_key')}": [I18n.t('general_error.params_missing_value', model: "like")])
      end
    end

    def validate_liker_presence
      render_error(404, "#{I18n.t('general_error.from_id_key')}": [I18n.t('general_error.not_found')]) if @liker.nil? || !@liker.presence?
    end

    # Only allow a trusted parameter "white list" through.
    def create_params
      @whitelisted = params.require(:like).permit(:from_type, :from_id)
      @whitelisted = @whitelisted.merge(likeable_id: params[@class + "_id"], likeable_type: @likeable_type)
    end

    def convert_hashids
      if @whitelisted["likeable_type"] || @whitelisted["likeable_id"]
        likeable = @whitelisted["likeable_type"].find(@whitelisted["likeable_id"])
        @whitelisted["likeable_id"] = likeable.id
      end

      if @whitelisted["liker_type"] || @whitelisted["liker_id"]
        liker = @whitelisted["liker_type"].find(@whitelisted["liker_id"])
        @whitelisted["liker_id"] = liker.id
      end
    end
end
