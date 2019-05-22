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
  credentials_path = if ENV["RACK_ENV"] == "test"
                       File.expand_path("../test/users.yml", __FILE__)
                     else
                       File.expand_path("../users.yml", __FILE__)
                     end
  YAML.load_file(credentials_path)
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
  file_path = File.join(data_path, filename)

  File.write(file_path, content)
  session[:message] = "#{filename} has been created."
  redirect "/"
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
  redirect "/"
end

def increment_file_number(basename)
  basename.sub(/(?<=\()\d+(?=\)\z)/) { |val| val.to_i + 1 }
end

get "/" do
  @files = list_of_current_files
  sort = params[:sort]
  sort == 'descending' ? @files.sort! { |a, b| b <=> a} : @files.sort!
  
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

get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  @filename = params[:filename]
  @content = File.read(file_path)

  erb :edit_doc
end

post "/create" do
  require_signed_in_user

  filename = params[:filename].to_s
  file_ext = File.extname(filename)

  if invalid_name?(filename)
    session[:message] = "A name is required."
    status 422
    erb :new
  elsif invalid_ext?(file_ext)
    file_extentions = VALID_FILE_EXT.join(', ')
    message = "Please use a valid file extention: #{file_extentions}."
    session[:message] = message
    status 422
    erb :new
  else
    create_file(filename) unless file_exists?(filename)
  end
end

post "/:filename" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

post "/:filename/destroy" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])

  File.delete(file_path)

  session[:message] = "#{params[:filename]} has been deleted."
  redirect "/"
end

post "/:filename/duplicate" do
  require_signed_in_user

  file_path = File.join(data_path, params[:filename])
  file_ext = File.extname(params[:filename])
  contents = File.read(file_path)
  basename = File.basename(params[:filename], ".*")

  new_filename = if basename.match?(/\(\d+\)\z/)
                   "#{increment_file_number(basename)}#{file_ext}"
                 else
                   "#{basename}(2)#{file_ext}"
                 end

  create_file(new_filename, contents) unless file_exists?(new_filename)
end
























