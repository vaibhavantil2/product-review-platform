require "letter_avatar/has_avatar"

class Company < Reviewer
  include SwaggerDocs::Company
  include LetterAvatar::HasAvatar
  include Statistics::Companies
  include Statistics::ScoreAggregator
  include Imageable
  mount_uploader :image, ImageUploader

  include Liker
  include Commenter

  # These refer to the reviews written by a claimant company
  # (different from reviews_count, see models/concerns/statistics/companies.rb)
  has_many :reviews, dependent: :destroy, as: :reviewer
  alias_attribute :reviews_as_reviewer, :reviews
  has_many :likes, dependent: :destroy, as: :liker
  has_many :comments, dependent: :destroy, as: :commenter

  has_many :company_reviewables, dependent: :destroy
  has_many :industry_companies, dependent: :destroy
  has_many :projects, through: :company_reviewables, source: :reviewable, source_type: "Project"
  has_many :products, through: :company_reviewables, source: :reviewable, source_type: "Product"
  has_many :services, through: :company_reviewables, source: :reviewable, source_type: "Service"
  has_many :industries, through: :industry_companies

  validates_presence_of :name, :aggregate_score, :reviews_count
  validates_uniqueness_of :uen, allow_blank: true, allow_nil: true
  validates_presence_of :description, allow_blank: true
  validates :url, allow_blank: true, url: true
  validates :image, file_size: { less_than: 1.megabytes }

  def grants(filter_by = nil, sort_by = nil, desc = nil)
    accepted_filter = valid_reviewable_filter(filter_by)
    accepted_sorter = valid_reviewable_sorter(sort_by)
    grants = get_reviews_as_vendor(accepted_filter).pluck(:grant_id)
    if grants.nil?
      []
    else
      @grant_list = Grant.kept.where(id: grants)
      handle_grant_sort(accepted_sorter, desc) if accepted_sorter.present?

      @grant_list.respond_to?(:distinct) ? @grant_list.distinct : @grant_list.uniq
    end
  end

  def offerings(sort_by = nil)
    results = (products.kept + services.kept + projects.kept)
    results = results.sort_by { |offering| offering.send(sort_by) }.reverse! if sort_by.present?
    results.empty? ? [] : results
  end

  def reviews_as_vendor(filter_by_score = nil, sort_by = nil)
    accepted_score_type = valid_review_score_filter(filter_by_score)
    accepted_sorter = valid_review_sorter(sort_by)
    @results = get_reviews_as_vendor
    handle_reviews_filter(accepted_score_type) if accepted_score_type.present?
    @results = @results.sort_by { |review| review.send(sort_by) }.reverse! if accepted_sorter.present?
    @results.empty? ? [] : @results
  end

  def aspects(filter_by_score = nil, sort_by = nil, count = nil)
    review_list = reviews_as_vendor(filter_by_score)
    accepted_sorter = valid_aspect_sorter(sort_by)
    @results = review_list.flat_map(&:aspects).select { |aspect| aspect.discarded_at.nil? }
    accepted_sorter.present? ? handle_aspects_sort(accepted_sorter, count) : @results = @results.uniq
    @results.empty? ? [] : @results
  end

  def clients(filter_by = nil, sort_by = nil, desc = nil)
    accepted_filter = valid_reviewable_filter(filter_by)
    accepted_sorter = valid_reviewable_sorter(sort_by)
    reviewers = get_reviews_as_vendor(accepted_filter).pluck(:reviewer_id)
    if reviewers.nil?
      []
    else
      client_list = Company.kept.where(id: reviewers.uniq)
      if accepted_sorter.present?
        return client_list.order(accepted_sorter => :asc) if desc.nil? || desc == "false"
        return client_list.order(accepted_sorter => :desc)
      end
      client_list
    end
  end

  def reviewable_industries(filter_by = nil)
    accepted_filter = valid_reviewable_filter(filter_by)
    reviewers = get_reviews_as_vendor(accepted_filter).pluck(:reviewer_id)
    if reviewers.nil?
      []
    else
      company_ids = Company.kept.where(id: reviewers.uniq).pluck(:id)
      if company_ids.nil?
        []
      else
        industry_ids = IndustryCompany.kept.where(company_id: company_ids).pluck(:industry_id).uniq
        if industry_ids.nil?
          []
        else
          Industry.kept.where(id: industry_ids)
        end
      end
    end
  end

  def set_reviews_count
    self.reviews_count = Review.kept.where(vendor_id: id).count
    save!
    reload
  end

  def set_aggregate_score
    self.aggregate_score = reviews_count > 0 ? calculate_aggregate_score(get_reviews_as_vendor) : 0.0
    save!
    reload
  end

  # rubocop:disable Metrics/AbcSize
  def get_reviews_as_vendor(filter_by = nil)
    case filter_by
    when 'Product'
      Review.match_reviewable(id, products.kept.pluck(:id), "Product").kept
    when 'Service'
      Review.match_reviewable(id, services.kept.pluck(:id), "Service").kept
    when 'Project'
      Review.match_reviewable(id, projects.kept.pluck(:id), "Project").kept
    else
      (Review.match_reviewable(id, products.kept.pluck(:id), "Product").kept +
        Review.match_reviewable(id, services.kept.pluck(:id), "Service").kept +
        Review.match_reviewable(id, projects.kept.pluck(:id), "Project").kept)
    end
  end
  # rubocop:enable Metrics/AbcSize

  class << self
    def sort(sort_by)
      kept.order(sort_by => :desc)
    end
  end

  def self.uen_query_sanitizer(uen)
    find_by(sanitize_sql(['lower(uen) =?', uen]))
  end

  def self.name_query_sanitizer(name)
    find_by(sanitize_sql(['lower(name) =?', name]))
  end

  private

  # e.g. score:1
  def handle_reviews_filter(accepted_score_type)
    @results.delete_if do |review|
      review.score != Review.const_get(accepted_score_type)
    end
  end

  def valid_review_score_filter(filter_by_score)
    valid_score_type = ['POSITIVE', 'NEUTRAL', 'NEGATIVE']
    valid_score_type.include?(filter_by_score) ? filter_by_score : nil
  end

  def valid_review_sorter(sort_by)
    valid_sorters = ['created_at']
    valid_sorters.include?(sort_by) ? sort_by : nil
  end

  def valid_aspect_sorter(sort_by)
    valid_sorters = ['aspects_count']
    valid_sorters.include?(sort_by) ? sort_by : nil
  end

  def handle_aspects_sort(accepted_sorter, count)
    case accepted_sorter
    when 'aspects_count'
      @results = @results.group_by(&:name).map { |_k, v| { aspect: v.first, count: v.length } }.sort_by { |v| -v[:count] }
      @results = @results.flat_map { |result| result.first.last } if count != 'true'
    end
  end

  def handle_grant_sort(accepted_sorter, desc)
    case accepted_sorter
    when 'reviews_count'
      @grant_list = @grant_list.group_by { |grant| grant }.map { |k, v| [k, v.length] }.to_h.sort_by { |_k, v| -v }.map(&:first)
      @grant_list.reverse! if desc != "true"
    end
  end

  def valid_grant_sorter(sort_by)
    valid_sorters = ['reviews_count']
    valid_sorters.include?(sort_by) ? sort_by : nil
  end

  def valid_reviewable_filter(filter_by)
    valid_filters = ['Product', 'Service', 'Project']
    valid_filters.include?(filter_by) ? filter_by : nil
  end

  def valid_reviewable_sorter(sort_by)
    valid_sorters = ['reviews_count', 'created_at']
    valid_sorters.include?(sort_by) ? sort_by : nil
  end

  def set_discard
    if discarded?
      CompanyReviewable.where(company_id: id).find_each do |company_reviewable|
        company_reviewable.discard
        company_reviewable.save!
      end
    end
  end
end
