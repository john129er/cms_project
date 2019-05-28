require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "pry"
require "bcrypt"

VALID_FILE_EXT = [".txt", ".md"]

configure do
  enable :sessions
  set :session_secret, "secret"
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def load_user_credentials
  YAML.load_file(credentials_path)
end

def credentials_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
end

def session
  last_request.env["rack.session"]
end

def signed_in?
  session.key?(:username)
end

def require_signed_in_user
  return if signed_in?
  session[:message] = "You must be signed in to do that."
  redirect "/"
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_pass = BCrypt::Password.new(credentials[username])
    bcrypt_pass == password
  else
    false
  end
end

def create_file(filename, content="")
  File.write(file_path(filename), content)
  session[:message] = "#{filename} has been created."
end

def invalid_name?(filename)
  filename.empty?
end

def invalid_ext?(file_ext)
  !VALID_FILE_EXT.include?(file_ext)
end

def list_of_current_files
  pattern = File.join(data_path, "*")
  Dir.glob(pattern).map { |path| File.basename(path) }
end

def file_exists?(filename)
  files = list_of_current_files
  return unless files.include?(filename)

  session[:message] = "#{filename} already exists."
end

def file_path(file_name)
  File.join(data_path, file_name)
end

def invalid_filename_error
  session[:message] = "A name is required."
  status 422
  erb :new
end

def invalid_extention_error
  file_extentions = VALID_FILE_EXT.join(', ')
  message = "Please use a valid file extention: #{file_extentions}."
  session[:message] = message
  status 422
  erb :new
end

def invalid_username?(username)
  credentials = load_user_credentials
  credentials.key?(username)
end

def invalid_password?(password)
  !(password.size >= 5 && password.match?(/\A\w{5,}\z/))
end

def store_credentials(username, password)
  credentials = load_user_credentials
  hashed_password = BCrypt::Password.create(password).to_s
  credentials[username] = hashed_password
  File.write(credentials_path, credentials.to_yaml)
end

get "/" do
  @files = list_of_current_files
  sort = params[:sort]
  sort == 'descending' ? @files.sort! { |a, b| b <=> a } : @files.sort!

  erb :index
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = "Welcome #{username}!"
    redirect "/"
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/new" do
  require_signed_in_user

  erb :new
end

get "/signup" do
  erb :signup
end

get "/:filename" do
  if File.file?(file_path(params[:filename]))
    load_file_content(file_path(params[:filename]))
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  require_signed_in_user

  @filename = params[:filename]
  @content = File.read(file_path(params[:filename]))

  erb :edit_doc
end

post "/create" do
  require_signed_in_user

  @filename = params[:filename].to_s
  @content = params[:content]
  file_ext = File.extname(@filename)

  if invalid_name?(@filename)
    invalid_filename_error
  elsif invalid_ext?(file_ext)
    invalid_extention_error
  else
    create_file(@filename, @content) unless file_exists?(@filename)
    redirect "/"
  end
end

post "/signup" do
  @username = params[:username]
  password = params[:password]

  if invalid_username?(@username)
    session[:message] = "Username already exists."
    status 422
    erb :signup
  elsif invalid_password?(password)
    session[:message] = "Password is invalid."
    status 422
    erb :signup
  else
    store_credentials(@username, password)
    session[:message] = "Signup success!"
    redirect "/users/signin"
  end
end

post "/:filename" do
  require_signed_in_user

  File.write(file_path(params[:filename]), params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/destroy" do
  require_signed_in_user

  File.delete(file_path(params[:filename]))

  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end

post "/:filename/duplicate" do
  require_signed_in_user

  @filename = params[:filename]
  @content = File.read(file_path(@filename))

  erb :new
end
