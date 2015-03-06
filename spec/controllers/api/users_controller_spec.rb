require "rails_helper"

RSpec.configure do |c|
  c.include ModelHelper
end

describe Api::UsersController do

  before :each do
    login_users
    @api_key = APP_CONFIG["api_key"]
  end

  describe "POST create" do
    context "with valid parameters and api_key" do
      it "should return a user object with id" do
        post :create, api_key: @api_key, user: {username: "Testuser", name: "John Doe", role: "ADMIN"}
        expect(json['user']['id']).to_not be nil
        expect(response.status).to eq 201
      end
    end
    context "With invalid role" do
      it "should return an error object" do
        post :create, api_key: @api_key, user: {username: "Testuser", name: "John Doe", role: "FOO"}
        expect(json['error']).to_not be nil
        expect(json['user']).to be nil
        expect(response.status).to eq 422
      end
    end
    context "with valid parameters and authorized user" do
      it "should return a user object with id" do
        request.env["HTTP_AUTHORIZATION"] = "Token #{@admin_user_token}"
        post :create, user: {username: "Testuser", name: "John Doe", role: "ADMIN"}
        expect(response.status).to eq 201
        expect(json['user']['id']).to_not be nil
      end
    end
    context "with valid parameters and unauthorized user" do
      it "should return an error object" do
        request.env["HTTP_AUTHORIZATION"] = "Token #{@operator_user_token}"
        post :create, user: {username: "Testuser", name: "John Doe", role: "ADMIN"}
        expect(response.status).to eq 403
        expect(json['error']).to_not be nil
        expect(json['user']).to be nil
      end
    end
  end

  describe "GET index" do
    context "with existing users" do
      it "should return a list of users" do
        get :index, api_key: @api_key
        expect(json['users']).to_not be nil
        expect(json['users'][0]['id']).to be_an(Integer)
      end
    end
  end

  describe "GET show" do
    context "an existing user" do
      it "should return a single user object" do
        user = create(:admin_user)
        get :show, api_key: @api_key, id: user.id
        expect(json['user']).to_not be nil
        expect(json['user']['id']).to be_an(Integer)
      end
    end
    context "a non existing user" do
      it "should return an error object" do
        get :show, api_key: @api_key, id: -1
        expect(json['error']).to_not be nil
      end
      it "should return status 404" do
        get :show, api_key: @api_key, id: -1
        expect(response.status).to eq 404
      end
    end
  end
end