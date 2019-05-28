ENV["RACK_ENV"] = "test"

require "fileutils"

require "minitest/autorun"
require "rack/test"

require_relative "../app"

class AppTest < Minitest::Test
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
  
  def setup
    FileUtils.mkdir_p(data_path)
  end
  
  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm(credentials_path) if File.exist?(credentials_path)
  end
  
  def create_yaml_file
    content = {
      "admin" => "$2a$10$XSyY62jdyxrhANvP2yWAVeDyEirtwDzCgx9Q5cAhufPhH0OYhlVXi"
    }

    File.open(credentials_path, "w") do |file|
      file.write(content.to_yaml)
    end
  end
  
  def create_document(name, content="")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end
  
  def admin_session
    { "rack.session" => { username: "admin" } }
  end
  
  def test_index
    create_document "about.md"
    create_document "changes.txt"
    
    get "/"
    
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end
  
  def test_viewing_text_document
    create_document "history.txt", "Magic core set"
    
    get "/history.txt"
    
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Magic core set"
  end
  
  def test_viewing_markdown_document
    create_document "about.md", "**A cylinder mower**"
    
    get "/about.md"
    
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<strong>A cylinder mower</strong>"
  end
  
  def test_document_not_found
    get "/notafile.ext"

    assert_equal 302, last_response.status
    assert_equal "notafile.ext does not exist.", session[:message]
  end
  
  def test_editing_document
    create_document "changes.txt"
  
    get "/changes.txt/edit", {}, admin_session
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end
  
  def test_editing_document_signed_out
    get "/history.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_updating_document
    create_document "changes.txt"
    post "/changes.txt", {content: "new content"}, admin_session
    
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end
  
  def test_updating_document_signed_out
    post "/changes.txt", content: "new content"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_view_new_document_form
    get "/new", {}, admin_session
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end
  
  def test_view_new_document_form_signed_out
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_create_new_document
    post "/create", {filename: "file.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "file.txt has been created.", session[:message]
    
    get "/"
    assert_includes last_response.body, "file.txt"
  end
  
  def test_create_new_document_signed_out
    post "/create", filename: "test.txt"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_create_new_document_without_name
    post "/create", {filename: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end
  
  def test_create_new_document_bad_file_ext
    post "/create", {filename: "test"}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Please use a valid file extension:"
  end
  
  def test_create_new_document_with_same_name
    create_document("file.txt")
    
    post "/create", {filename: "file.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "file.txt already exists.", session[:message]
  end
  
  def test_delete_file
    create_document "history.txt"
    
    post "/history.txt/destroy" , {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "history.txt has been deleted.", session[:message]
    
    get "/"
    refute_includes last_response.body, %q(href="/test.txt")
  end
  
  def test_delete_file_signed_out
    create_document("test.txt")

    post "/test.txt/destroy"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_signin_form
    get "/users/signin"
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form"
    assert_includes last_response.body, %q(<button type="submit")
  end
  
  def test_signin_success
    create_yaml_file
    
    post "/users/signin", {username: "admin", password: "secret"}
    assert_equal 302, last_response.status
    assert_equal "Welcome #{session[:username]}!", session[:message]
    assert_equal "admin", session[:username]
    
    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end
  
  def test_signin_failure
    create_yaml_file
    
    post "/users/signin", {username: "admin", password: "admin"}
    
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid credentials"
  end
  
  def test_signout
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"
    
    post "/users/signout"
    assert_equal "You have been signed out.", session[:message]
    
    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign In"
  end
  
  def test_file_duplication_form
    create_document("test.txt", "new content")
    
    post "/test.txt/duplicate", {filename: "test.txt"}, admin_session
    assert_includes last_response.body, %q(value="test.txt")
    assert_includes last_response.body, "new content"
  end
  
  def test_file_duplication_signed_out
    create_document("test.txt")

    post "/test.txt/duplicate"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end
  
  def test_view_signin_form
    get "/signup"
    
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form"
    assert_includes last_response.body, "<p>"
    assert_includes last_response.body, %q(<button type="submit")
  end
  
  def test_signup_invalid_username
    create_yaml_file
    
    post "/signup", {username: "admin"}
    
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Username already exists."
  end
  
  def test_signup_invalid_password_length
    create_yaml_file
    
    post "/signup", {username: 'john', password: 'size'}
    
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Password is invalid."
  end
  
  def test_signup_invalid_password_characters
    create_yaml_file
    
    post "/signup", {username: 'john', password: 'paper#$'}
    
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Password is invalid."
  end
  
  def test_signup_successful
    create_yaml_file
    
    post "/signup", {username: 'john', password: 'goodpassword'}
    
    assert_equal last_response.status, 302
    assert_equal "Signup success!", session[:message]
  end
end




















