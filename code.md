# Rails 8 “Signalboard” — A Real‑Time Feature Request Board (Solid Queue/Cache/Cable, Built‑in Auth, Turbo 8, Stimulus, Tailwind, Kamal on DigitalOcean)

**What you’ll build:** **Signalboard**, a TUI‑styled **Feature Request Board** where users propose features,
vote, comment, and watch **real‑time** updates. We’ll use Rails 8 defaults — **Solid Queue** (jobs), **Solid Cache** (DB cache),
**Solid Cable** (Action Cable without Redis), **built‑in authentication**, **Turbo 8 + Stimulus**, and **Tailwind** — then deploy with **Kamal** on DigitalOcean.
Every interesting line is explained: **what it does** and **why**.

## Table of Contents

- 1. Introduction & Goals
- 2. Environment Setup
- 3. Create the App (`rails new`) & First Run
- 4. Built‑in Authentication (Sessions, Password Reset, Sign‑Up)
- 5. Web‑TUI Layout with Tailwind
- 6. Domain Models & Migrations
- 7. Routes & Controllers
- 8. Turbo 8 Views: Frames, Streams, Morphing
- 9. Real‑Time Notifications (Solid Cable)
- 10. In‑App Notifications (Turbo Streams)
- 11. Email & Daily Digest (Mailer + Solid Queue)
- 12. Recurring Jobs with Solid Queue
- 13. Solid Cache for Project Stats
- 14. Stimulus Controllers: Optimistic UI, Clipboard, Toasts
- 15. Advanced Stimulus: Drag‑and‑Drop Reordering
- 16. Live Search & Filter (Turbo Frames)
- 17. Theme Switcher (TUI Night/Day)
- 18. Security & Hardening
- 19. Production Configuration
- 20. Testing with Minitest
- 21. Recurring Jobs Deep Dive
- 22. Drag‑and‑Drop System Test
- 23. Monitoring & Health (Kamal, /up, logs, metrics)
- Appendix: Kamal Deploy (DO)

## 1) Introduction & Goals

We’ll build a **Feature Request Board** for projects with voting, comments, status, and live updates. The UI uses a **web TUI** style (monospace,
bordered cards, low‑color palette with neon accents), keeping markup clean and short.

## 2) Environment Setup

```bash
ruby -v     # 3.3+
gem install rails
rails -v    # 8.x
```

SQLite for dev; importmap and tailwindcss‑rails mean no Node bundler is required.

## 3) Create the App (`rails new`) & First Run

```bash
rails new signalboard --css=tailwind --database=sqlite3
cd signalboard
bin/setup
bin/dev
```

- `--css=tailwind` wires Tailwind with a watcher.

- **Importmap** ships Turbo & Stimulus without bundling.

- **Propshaft** handles assets.

Open <http://localhost:3000> to verify it boots.

## 4) Built‑in Authentication

```bash
bin/rails generate authentication
bin/rails db:migrate
```

This creates **User**, **Session**, sessions controller, password mailer, and helpers. We add **registrations** for sign‑up.

```ruby
# config/routes.rb (auth bits)
resource :session, only: [:new, :create, :destroy]
resources :passwords, only: [:new, :create, :edit, :update]
resources :registrations, only: [:new, :create]
```

```ruby
# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: [:new, :create]

  def new; @user = User.new; end

  def create
    @user = User.new(user_params)
    if @user.save
      start_new_session_for(@user)
      redirect_to root_path, notice: "Welcome to Signalboard!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
  def user_params
    params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
  end

  def start_new_session_for(user)
    s = user.sessions.create!
    cookies.signed.permanent[:session_token] = { value: s.token, httponly: true }
  end
end
```

```erb
<!-- app/views/registrations/new.html.erb -->
<div class="mx-auto max-w-sm bg-white border rounded-xl p-6">
  <h1 class="text-xl font-semibold mb-4">Create your account</h1>
  <%= form_with model: @user, url: registrations_path, class: "space-y-4" do |f| %>
    <div>
      <%= f.label :name, class: "block text-sm mb-1" %>
      <%= f.text_field :name, class: "w-full rounded-lg border px-3 py-2" %>
    </div>
    <div>
      <%= f.label :email_address, class: "block text-sm mb-1" %>
      <%= f.email_field :email_address, class: "w-full rounded-lg border px-3 py-2" %>
    </div>
    <div class="grid grid-cols-2 gap-3">
      <div>
        <%= f.label :password, class: "block text-sm mb-1" %>
        <%= f.password_field :password, class: "w-full rounded-lg border px-3 py-2" %>
      </div>
      <div>
        <%= f.label :password_confirmation, class: "block text-sm mb-1" %>
        <%= f.password_field :password_confirmation, class: "w-full rounded-lg border px-3 py-2" %>
      </div>
    </div>
    <div class="flex items-center justify-between">
      <%= f.submit "Sign up", class: "rounded-lg bg-black text-white px-4 py-2" %>
      <%= link_to "Have an account? Sign in", new_session_path, class: "text-sm text-gray-600" %>
    </div>
  <% end %>
</div>
```

## 5) Web‑TUI Layout with Tailwind

```erb
<!-- app/views/layouts/application.html.erb -->
<!DOCTYPE html>
<html lang="en" class="h-full bg-zinc-950">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><%= content_for(:title) || "Signalboard" %></title>
    <meta name="view-transition" content="same-origin">
    <meta name="turbo-refresh-method" content="morph">
    <meta name="turbo-refresh-scroll" content="preserve">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
    <style>
      :root { --crt: 0.35 }
      .crt::after {
        content:""; position:fixed; inset:0; pointer-events:none;
        background: repeating-linear-gradient(0deg, rgba(255,255,255,0.02), rgba(255,255,255,0.02) 1px, transparent 1px, transparent 2px);
        mix-blend-mode: overlay; opacity: var(--crt);
      }
    </style>
  </head>
  <body class="h-full text-zinc-100 font-mono crt">
    <header class="border-b border-zinc-800 bg-zinc-900/70 backdrop-blur">
      <nav class="mx-auto max-w-6xl flex items-center justify-between p-3">
        <div class="flex items-center gap-3">
          <span class="inline-flex h-7 w-7 items-center justify-center rounded-md bg-emerald-500 text-zinc-900 font-bold">S</span>
          <%= link_to "Signalboard", root_path, class: "text-base font-semibold" %>
        </div>
        <div class="flex items-center gap-4 text-sm">
          <%= link_to "Projects", projects_path, class: "hover:text-white" %>
          <%= link_to "Notifications", notifications_path, class: "relative hover:text-white" %>
          <span data-role="unread-badge"
            class="absolute -right-3 -top-2 inline-flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-emerald-500/90 px-1 text-[10px] text-zinc-900">0</span>
          <% if authenticated? %>
            <%= button_to "Sign out", session_path, method: :delete, class: "hover:text-white" %>
          <% else %>
            <%= link_to "Sign in", new_session_path, class: "hover:text-white" %>
          <% end %>
        </div>
      </nav>
    </header>
    <main class="mx-auto max-w-6xl p-4">
      <% flash.each do |type, message| %>
        <div class="mb-4 rounded border border-zinc-800 bg-zinc-900 px-4 py-2 text-sm"><%= message %></div>
      <% end %>
      <%= yield %>
    </main>
  </body>
</html>
```

## 6) Domain Models & Migrations

```bash
bin/rails g model Project name:string description:text
bin/rails g model FeatureRequest project:references user:references title:string body:text status:string:index position:integer:index
bin/rails g model Comment feature_request:references user:references body:text
bin/rails g model Vote feature_request:references user:references
bin/rails g model Subscription project:references user:references
bin/rails g model Notification user:references notifiable:references{polymorphic} kind:string read_at:datetime
bin/rails db:migrate
```

```ruby
# app/models/project.rb
class Project < ApplicationRecord
  has_many :feature_requests, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :subscribers, through: :subscriptions, source: :user
  validates :name, presence: true, length: { maximum: 80 }
end
```

```ruby
# app/models/feature_request.rb
class FeatureRequest < ApplicationRecord
  belongs_to :project
  belongs_to :user
  has_many :comments, dependent: :destroy
  has_many :votes, dependent: :destroy

  STATUSES = %w[proposed planned in_progress shipped].freeze
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  after_create_commit -> { broadcast_prepend_later_to [project, :feature_requests] }
  after_update_commit -> { broadcast_replace_later_to self }
  after_destroy_commit -> { broadcast_remove_to [project, :feature_requests] }

  default_scope { order(position: :asc, created_at: :asc) }
  def votes_count = votes.count
end
```

```ruby
# app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :feature_request
  belongs_to :user
  validates :body, presence: true

  after_create_commit -> {
    broadcast_append_later_to [feature_request, :comments]
    Notification.create_for!(users: feature_request.project.subscribers, notifiable: self, kind: "comment")
  }
end
```

```ruby
# app/models/vote.rb
class Vote < ApplicationRecord
  belongs_to :feature_request
  belongs_to :user
  validates :user_id, uniqueness: { scope: :feature_request_id }
end
```

```ruby
# app/models/subscription.rb
class Subscription < ApplicationRecord
  belongs_to :project
  belongs_to :user
  validates :user_id, uniqueness: { scope: :project_id }
end
```

```ruby
# app/models/notification.rb
class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :notifiable, polymorphic: true
  scope :unread, -> { where(read_at: nil) }

  def self.create_for!(users:, notifiable:, kind:)
    users.find_each { |u| create!(user: u, notifiable: notifiable, kind: kind) }
  end
end
```

## 7) Routes & Controllers

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "projects#index"

  resource :session, only: [:new, :create, :destroy]
  resources :passwords, only: [:new, :create, :edit, :update]
  resources :registrations, only: [:new, :create]

  resources :projects do
    resources :feature_requests do
      collection { post :reorder }
      resources :comments, only: [:create, :destroy]
      resources :votes, only: [:create, :destroy]
    end
    resources :subscriptions, only: [:create, :destroy]
  end

  resources :notifications, only: [:index] do
    collection { post :mark_all_read }
  end

  get "/up", to: "health#show"
  get "/metrics", to: "metrics#show"
end
```

```ruby
# app/controllers/projects_controller.rb
class ProjectsController < ApplicationController
  def index
    @projects = Project.joins(:subscriptions).where(subscriptions: { user_id: current_user.id }).distinct
  end
  def show
    @project = Project.find(params[:id])
    @feature_request = @project.feature_requests.new
  end
  def new; @project = Project.new; end
  def create
    @project = Project.new(project_params)
    if @project.save
      Subscription.find_or_create_by!(project: @project, user: current_user)
      redirect_to @project, notice: "Project created"
    else
      render :new, status: :unprocessable_entity
    end
  end
  def edit;  @project = Project.find(params[:id]); end
  def update
    @project = Project.find(params[:id])
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  def destroy
    @project = Project.find(params[:id])
    @project.destroy
    redirect_to projects_path, notice: "Project deleted"
  end
  private
  def project_params; params.require(:project).permit(:name, :description); end
end
```

```ruby
# app/controllers/feature_requests_controller.rb
class FeatureRequestsController < ApplicationController
  before_action :set_project

  def index
    @feature_requests = @project.feature_requests
    if params[:q].present?
      q = "%#{params[:q]}%"; @feature_requests = @feature_requests.where("title LIKE ? OR body LIKE ?", q, q)
    end
    @feature_requests = @feature_requests.where(status: params[:status]) if params[:status].present()
  end

  def show
    @feature_request = @project.feature_requests.find(params[:id])
    @comment = @feature_request.comments.new
  end

  def new; @feature_request = @project.feature_requests.new; end

  def create
    @feature_request = @project.feature_requests.new(fr_params.merge(user: current_user, status: "proposed", position: next_position))
    if @feature_request.save
      redirect_to [@project, @feature_request], notice: "Feature created"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit;    @feature_request = @project.feature_requests.find(params[:id]); end
  def update
    @feature_request = @project.feature_requests.find(params[:id])
    if @feature_request.update(fr_params)
      redirect_to [@project, @feature_request], notice: "Feature updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @feature_request = @project.feature_requests.find(params[:id])
    @feature_request.destroy
    redirect_to @project, notice: "Feature deleted"
  end

  def reorder
    ids = Array(params[:ids])
    FeatureRequest.transaction do
      ids.each_with_index { |id, idx| @project.feature_requests.where(id: id).update_all(position: idx + 1) }
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("project_#{@project.id}_feature_requests", partial: "feature_requests/list", locals: { project: @project }) }
      format.head :ok
    end
  end

  private
  def set_project; @project = Project.find(params[:project_id]); end
  def fr_params;   params.require(:feature_request).permit(:title, :body, :status); end
  def next_position; (@project.feature_requests.maximum(:position) || 0) + 1; end
end
```

```ruby
# app/controllers/comments_controller.rb
class CommentsController < ApplicationController
  before_action :set_feature_request
  def create
    @comment = @feature_request.comments.new(comment_params.merge(user: current_user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to [@feature_request.project, @feature_request], notice: "Comment added" }
      end
    else
      render "feature_requests/show", status: :unprocessable_entity
    end
  end
  def destroy
    @comment = @feature_request.comments.find(params[:id])
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to [@feature_request.project, @feature_request], notice: "Comment deleted" }
    end
  end
  private
  def set_feature_request; @feature_request = FeatureRequest.find(params[:feature_request_id]); end
  def comment_params; params.require(:comment).permit(:body); end
end
```

```ruby
# app/controllers/votes_controller.rb
class VotesController < ApplicationController
  before_action :set_feature_request
  def create
    Vote.find_or_create_by!(feature_request: @feature_request, user: current_user)
    broadcast_votes; respond_to { |format| format.turbo_stream; format.html { redirect_to [@feature_request.project, @feature_request] } }
  end
  def destroy
    Vote.where(feature_request: @feature_request, user: current_user).destroy_all
    broadcast_votes; respond_to { |format| format.turbo_stream; format.html { redirect_to [@feature_request.project, @feature_request] } }
  end
  private
  def set_feature_request; @feature_request = FeatureRequest.find(params[:feature_request_id]); end
  def broadcast_votes
    FeatureRequest.broadcast_replace_later_to @feature_request, target: dom_id(@feature_request, :vote), partial: "feature_requests/vote", locals: { feature_request: @feature_request }
  end
end
```

```ruby
# app/controllers/subscriptions_controller.rb
class SubscriptionsController < ApplicationController
  before_action :set_project
  def create
    Subscription.find_or_create_by!(project: @project, user: current_user)
    respond_to { |format| format.turbo_stream; format.html { redirect_to @project, notice: "Subscribed" } }
  end
  def destroy
    Subscription.where(project: @project, user: current_user).destroy_all
    respond_to { |format| format.turbo_stream; format.html { redirect_to @project, notice: "Unsubscribed" } }
  end
  private
  def set_project; @project = Project.find(params[:project_id]); end
end
```

```ruby
# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  def index
    @notifications = current_user.notifications.order(created_at: :desc).limit(50)
  end
  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    respond_to { |format| format.turbo_stream; format.html { redirect_to notifications_path, notice: "All caught up" } }
  end
end
```

## 8) Turbo 8 Views: Frames, Streams, Morphing

```erb
<!-- app/views/projects/index.html.erb -->
<div class="flex items-center justify_between mb-6">
  <h1 class="text-2xl font-semibold">Projects</h1>
  <%= link_to "New project", new_project_path, class: "rounded-md bg-emerald-500 text-zinc-900 px-4 py-2 font-semibold" %>
</div>
<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
  <% @projects.each do |project| %>
    <div class="rounded border border-zinc-800 bg-zinc-900 p-4">
      <div class="flex items-center justify-between">
        <h2 class="font-medium"><%= link_to project.name, project %></h2>
        <%= render "projects/subscribe_button", project: project %>
      </div>
      <p class="mt-2 text-sm text-zinc-400 line-clamp-3"><%= project.description %></p>
    </div>
  <% end %>
</div>
```

```erb
<!-- app/views/projects/_subscribe_button.html.erb -->
<div id="<%= dom_id(project, :subscribe_button) %>">
  <% subscribed = project.subscriptions.exists?(user: current_user) %>
  <% if subscribed %>
    <%= button_to "Unsubscribe", project_subscription_path(project), method: :delete, class: "text-xs text-zinc-300 hover:text-white" %>
  <% else %>
    <%= button_to "Subscribe", project_subscriptions_path(project), class: "text-xs text-zinc-100 hover:text-white" %>
  <% end %>
</div>
```

```erb
<!-- app/views/projects/_subscribe_button.turbo_stream.erb -->
<%= turbo_stream.replace dom_id(project, :subscribe_button) do %>
  <%= render "projects/subscribe_button", project: project %>
<% end %>
```

```erb
<!-- app/views/projects/show.html.erb -->
<div class="mb-6 flex items-start justify-between gap-4">
  <div>
    <h1 class="text-2xl font-semibold"><%= @project.name %></h1>
    <p class="text-zinc-400"><%= @project.description %></p>
  </div>
  <div class="flex items-center gap-2">
    <%= render "projects/subscribe_button", project: @project %>
    <%= link_to "Edit", edit_project_path(@project), class: "rounded border border-zinc-800 px-3 py-1.5" %>
  </div>
</div>

<div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
  <section class="lg:col-span-2">
    <div class="flex items-center justify-between mb-3">
      <h2 class="font-semibold">Feature Requests</h2>
    </div>
    <%= render "feature_requests/list", project: @project %>
    <div class="mt-6 rounded border border-zinc-800 bg-zinc-900 p-4">
      <%= render "feature_requests/form", project: @project, feature_request: @feature_request %>
    </div>
  </section>
  <aside>
    <%= render "projects/sidebar", project: @project %>
  </aside>
</div>
```

```erb
<!-- app/views/feature_requests/_list.html.erb -->
<%= turbo_stream_from [project, :feature_requests] %>
<div id="project_<%= project.id %>_feature_requests" data-controller="sortable" data-sortable-url-value="<%= reorder_project_feature_requests_path(project) %>">
  <% project.feature_requests.each do |feature_request| %>
    <div id="<%= dom_id(feature_request) %>" data-sortable-target="item" draggable="true"
         class="rounded border border-zinc-800 bg-zinc-900 p-4 mb-2 cursor-move">
      <%= render feature_request %>
    </div>
  <% end %>
</div>
```

```erb
<!-- app/views/feature_requests/_feature_request.html.erb -->
<div class="flex items-start justify-between">
  <div>
    <h3 class="font-medium"><%= link_to feature_request.title, [feature_request.project, feature_request] %></h3>
    <p class="text-xs text-zinc-400">by <%= feature_request.user.name || feature_request.user.email_address %></p>
  </div>
  <div class="text-right">
    <span class="text-[10px] rounded bg-zinc-800 px-2 py-1"><%= feature_request.status.humanize %></span>
    <div id="<%= dom_id(feature_request, :vote) %>"><%= render "feature_requests/vote", feature_request: feature_request %></div>
  </div>
</div>
```

```erb
<!-- app/views/feature_requests/_vote.html.erb -->
<% voted = feature_request.votes.exists?(user: current_user) %>
<div class="mt-1 text-xs text-zinc-400">
  ▲ <%= feature_request.votes_count %>
  <% if voted %>
    <%= button_to "Unvote", [feature_request, :votes], method: :delete, class: "ml-2 underline" %>
  <% else %>
    <%= button_to "Vote", [feature_request, :votes], class: "ml-2 underline" %>
  <% end %>
</div>
```

```erb
<!-- app/views/feature_requests/_form.html.erb -->
<%= form_with model: [project, feature_request], class: "space-y-3" do |f| %>
  <div><%= f.label :title, class: "block text-sm mb-1" %><%= f.text_field :title, class: "w-full rounded border border-zinc-800 bg-zinc-900 px-3 py-2" %></div>
  <div><%= f.label :body, class: "block text-sm mb-1" %><%= f.text_area :body, rows: 5, class: "w-full rounded border border-zinc-800 bg-zinc-900 px-3 py-2" %></div>
  <div class="flex items-center gap-3">
    <%= f.submit "Create", class: "rounded bg-emerald-500 text-zinc-900 px-4 py-2 font-semibold" %>
    <%= f.select :status, FeatureRequest::STATUSES, {}, class: "rounded border border-zinc-800 bg-zinc-900 px-3 py-2" %>
  </div>
<% end %>
```

```erb
<!-- app/views/feature_requests/show.html.erb -->
<% content_for :title, @feature_request.title %>
<div class="mb-6 flex items-center justify-between">
  <h1 class="text-2xl font-semibold"><%= @feature_request.title %></h1>
  <%= link_to "Back", project_path(@feature_request.project), class: "text-sm text-zinc-400 hover:text-zinc-200" %>
</div>
<div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
  <section class="lg:col-span-2 space-y-4">
    <article class="rounded border border-zinc-800 bg-zinc-900 p-4">
      <p class="text-zinc-100 whitespace-pre-wrap"><%= @feature_request.body %></p>
    </article>
    <%= turbo_stream_from [@feature_request, :comments] %>
    <div id="feature_request_<%= @feature_request.id %>_comments" class="space-y-3">
      <%= render @feature_request.comments.order(created_at: :asc) %>
    </div>
    <div class="rounded border border-zinc-800 bg-zinc-900 p-4">
      <%= render "comments/form", feature_request: @feature_request, comment: @comment %>
    </div>
  </section>
  <aside><%= render "projects/sidebar", project: @feature_request.project %></aside>
</div>
```

```erb
<!-- app/views/comments/_comment.html.erb -->
<div id="<%= dom_id(comment) %>" class="rounded border border-zinc-800 bg-zinc-900 p-3">
  <div class="flex items-center justify-between">
    <p class="text-sm text-zinc-100"><%= comment.body %></p>
    <% if comment.user == current_user %>
      <%= button_to "Delete", [comment.feature_request, comment], method: :delete, form: { data: { turbo_confirm: "Delete this comment?" } }, class: "text-[10px] text-zinc-400" %>
    <% end %>
  </div>
</div>
```

```erb
<!-- app/views/comments/_form.html.erb -->
<%= form_with model: [feature_request, comment], class: "space-y-3" do |f| %>
  <div><%= f.label :body, class: "block text-sm mb-1" %><%= f.text_area :body, rows: 3, class: "w-full rounded border border-zinc-800 bg-zinc-900 px-3 py-2" %></div>
  <%= f.submit "Comment", class: "rounded bg-emerald-500 text-zinc-900 px-4 py-2 font-semibold" %>
<% end %>
```

```erb
<!-- app/views/projects/_sidebar.html.erb -->
<% stats = (@project.respond_to?(:cached_stats) ? @project.cached_stats : {
  proposed: @project.feature_requests.where(status: :proposed).count,
  planned: @project.feature_requests.where(status: :planned).count,
  in_progress: @project.feature_requests.where(status: :in_progress).count,
  shipped: @project.feature_requests.where(status: :shipped).count
}) %>
<div class="rounded border border-zinc-800 bg-zinc-900 p-4">
  <h3 class="font-semibold mb-2">Overview</h3>
  <dl class="grid grid-cols-2 gap-2 text-sm">
    <dt class="text-zinc-400">Proposed</dt><dd><%= stats[:proposed] %></dd>
    <dt class="text-zinc-400">Planned</dt><dd><%= stats[:planned] %></dd>
    <dt class="text-zinc-400">In progress</dt><dd><%= stats[:in_progress] %></dd>
    <dt class="text-zinc-400">Shipped</dt><dd><%= stats[:shipped] %></dd>
  </dl>
</div>
```

## 9) Real‑Time Notifications (Solid Cable)

```yaml
# config/cable.yml
development: { adapter: async }
production: { adapter: solid_cable }
```

```bash
bin/rails g channel Notifications
```

```ruby
# app/channels/notifications_channel.rb
class NotificationsChannel < ApplicationCable::Channel
  def subscribed; stream_for current_user; end
end
```

```javascript
// app/javascript/channels/notifications_channel.js
import consumer from "./consumer";
export const NotificationsChannel = {
  subscribe() {
    return consumer.subscriptions.create("NotificationsChannel", {
      received(data) {
        const el = document.querySelector('[data-role="unread-badge"]');
        if (el) el.textContent = data.count;
      },
    });
  },
};
addEventListener("turbo:load", () => NotificationsChannel.subscribe());
```

```ruby
# app/models/notification.rb (append)
after_commit -> { NotificationsChannel.broadcast_to(user, { count: user.notifications.unread.count }) }
```

## 10) In‑App Notifications (Turbo Streams)

```ruby
# app/controllers/notifications_controller.rb (already added)
def index
  @notifications = current_user.notifications.order(created_at: :desc).limit(50)
end
def mark_all_read
  current_user.notifications.unread.update_all(read_at: Time.current)
  respond_to { |format| format.turbo_stream; format.html { redirect_to notifications_path, notice: "All caught up" } }
end
```

```erb
<!-- app/views/notifications/index.html.erb -->
<h1 class="text-xl font-semibold mb-4">Notifications</h1>
<div class="mb-3"><%= button_to "Mark all read", mark_all_read_notifications_path, class: "rounded border border-zinc-800 px-3 py-1.5" %></div>
<div id="notifications_list" class="space-y-2">
  <% @notifications.each do |n| %>
    <div class="rounded border border-zinc-800 bg-zinc-900 p-3 text-sm">
      <span class="text-zinc-400"><%= n.kind.humanize %></span> — <%= n.notifiable_type %> #<%= n.notifiable_id %>
      <% if n.read_at.nil? %><span class="ml-2 text-[10px] text-emerald-400">NEW</span><% end %>
    </div>
  <% end %>
</div>
```

## 11) Email & Daily Digest (Action Mailer + Solid Queue)

```bash
bin/rails g mailer DigestMailer
```

```ruby
# app/mailers/digest_mailer.rb
class DigestMailer < ApplicationMailer
  def daily(user); @user = user; mail to: @user.email_address, subject: "Your Signalboard digest"; end
end
```

```erb
<!-- app/views/digest_mailer/daily.html.erb -->
<h1>Your daily Signalboard digest</h1>
<ul>
  <% @user.subscriptions.includes(project: :feature_requests).each do |sub| %>
    <li><strong><%= sub.project.name %></strong>: <%= sub.project.feature_requests.order(updated_at: :desc).limit(5).pluck(:title).join(", ") %></li>
  <% end %>
</ul>
```

```ruby
# app/jobs/daily_digest_job.rb
class DailyDigestJob < ApplicationJob
  queue_as :low
  def perform(user_id)
    DigestMailer.daily(User.find(user_id)).deliver_now
  end
end
```

```ruby
# app/jobs/daily_digest_enqueue_job.rb
class DailyDigestEnqueueJob < ApplicationJob
  queue_as :low
  def perform
    User.joins(:subscriptions).distinct.find_each { |u| DailyDigestJob.perform_later(u.id) }
  end
end
```

## 12) Recurring Jobs with Solid Queue

```yaml
# config/recurring.yml
- job: "DailyDigestEnqueueJob"
  schedule: "0 8 * * *"
```

```yaml
# config/solid_queue.yml (example)
defaults: &defaults
  workers: 2
  threads: 5
production:
  <<: *defaults
  queues:
    default: { concurrency: 10 }
    low: { concurrency: 5 }
```

Run workers (with scheduler) in dev: `bin/rails jobs:work`. Change CRON to `* * * * *` to test quickly.

## 13) Solid Cache for Project Stats

```ruby
# app/models/project.rb (append)
def cached_stats
  Rails.cache.fetch([self, :stats], expires_in: 10.minutes) do
    {
      proposed: feature_requests.where(status: :proposed).count,
      planned: feature_requests.where(status: :planned).count,
      in_progress: feature_requests.where(status: :in_progress).count,
      shipped: feature_requests.where(status: :shipped).count
    }
  end
end
```

```ruby
# app/models/feature_request.rb (append)
after_commit :bust_project_stats, on: [:create, :update, :destroy]
private
def bust_project_stats; Rails.cache.delete([project, :stats]); end
```

## 14) Stimulus Controllers: Optimistic UI, Clipboard, Toasts

```javascript
// app/javascript/controllers/optimistic_controller.js
import { Controller } from "@hotwired/stimulus";
export default class extends Controller {
  static targets = ["form"];
  connect() {
    if (this.hasFormTarget) {
      const form = this.formTarget;
      form.addEventListener("submit", () => {
        form
          .querySelectorAll("button,input,select,textarea")
          .forEach((el) => (el.disabled = true));
      });
    }
  }
}
```

```javascript
// app/javascript/controllers/clipboard_controller.js
import { Controller } from "@hotwired/stimulus";
export default class extends Controller {
  static targets = ["source", "toast"];
  async copy() {
    const text = this.sourceTarget.value || this.sourceTarget.textContent;
    await navigator.clipboard.writeText(text);
    this.toastTarget.classList.remove("hidden");
    setTimeout(() => this.toastTarget.classList.add("hidden"), 1200);
  }
}
```

## 15) Advanced Stimulus: Drag‑and‑Drop Reordering

```javascript
// app/javascript/controllers/sortable_controller.js
import { Controller } from "@hotwired/stimulus";
export default class extends Controller {
  static targets = ["item"];
  static values = { url: String };
  connect() {
    this.dragging = null;
    this.itemTargets.forEach((el) => {
      el.addEventListener("dragstart", (e) => this.onDragStart(e));
      el.addEventListener("dragover", (e) => this.onDragOver(e));
      el.addEventListener("drop", (e) => this.onDrop(e));
    });
  }
  onDragStart(e) {
    this.dragging = e.currentTarget;
    e.dataTransfer.effectAllowed = "move";
  }
  onDragOver(e) {
    e.preventDefault();
    const t = e.currentTarget;
    if (!this.dragging || this.dragging === t) return;
    const r = t.getBoundingClientRect();
    const after = (e.clientY - r.top) / r.height > 0.5;
    t.parentNode.insertBefore(this.dragging, after ? t.nextSibling : t);
  }
  onDrop(e) {
    e.preventDefault();
    const ids = Array.from(
      this.element.querySelectorAll('[data-sortable-target="item"]'),
    ).map((el) => el.id.replace("feature_request_", ""));
    const fd = new FormData();
    ids.forEach((id) => fd.append("ids[]", id));
    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
          .content,
      },
      body: fd,
    });
  }
}
```

## 16) Live Search & Filter (Turbo Frames)

```javascript
// app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus";
export default class extends Controller {
  static targets = ["input"];
  static values = { delay: { type: Number, default: 250 } };
  connect() {
    this.timer = null;
  }
  query() {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      const q = this.inputTarget.value;
      const url = new URL(window.location);
      url.searchParams.set("q", q);
      Turbo.visit(url, { action: "replace" });
    }, this.delayValue);
  }
}
```

```erb
<!-- usage in index -->
<div data-controller="search" data-search-delay-value="300" class="mb-3">
  <input data-search-target="input" class="rounded border border-zinc-800 bg-zinc-900 px-3 py-2" placeholder="Filter..." value="<%= params[:q] %>"
         oninput="this.closest('[data-controller]')?.controller?.query()">
</div>
```

## 17) Theme Switcher (TUI Night/Day)

```javascript
// app/javascript/controllers/theme_controller.js
import { Controller } from "@hotwired/stimulus";
export default class extends Controller {
  static values = { crt: Number };
  connect() {
    document.documentElement.style.setProperty("--crt", this.crtValue || 0.35);
  }
  toggle() {
    const current =
      parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue("--crt"),
      ) || 0.35;
    document.documentElement.style.setProperty(
      "--crt",
      current > 0.2 ? 0 : 0.35,
    );
  }
}
```

## 18) Security & Hardening

- **CSRF**: Rails default.
- **CSP**: set in `config/initializers/content_security_policy.rb`.
- **Rate limiting**: Rack::Attack.
- **Cookies**: set `secure` in production.

## 19) Production Configuration

Use `bin/rails credentials:edit` for secrets. Configure Mailer host/SMTP. In `config/cable.yml`, set `production: adapter: solid_cable`. Prefer DO Managed Postgres and set `DATABASE_URL`.

## 20) Testing with Minitest

```ruby
# test/application_system_test_case.rb
require "test_helper"; require "capybara/rails"
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
end
```

```ruby
# test/models/feature_request_test.rb
require "test_helper"
class FeatureRequestTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Alpha")
    @user = User.create!(email_address: "a@x.com", password: "p", password_confirmation: "p")
  end
  test "valid with title" do
    fr = FeatureRequest.new(project: @project, user: @user, title: "X", status: "proposed")
    assert fr.valid?
  end
end
```

## 21) Recurring Jobs Deep Dive

```ruby
travel_to Time.zone.parse("2025-08-08 08:00") do
  assert_enqueued_with(job: DailyDigestJob) { DailyDigestEnqueueJob.perform_now }
end
```

## 22) Drag‑and‑Drop System Test

```ruby
# test/system/reorder_test.rb
require "application_system_test_case"
class ReorderTest < ApplicationSystemTestCase
  test "reorder" do
    # (Pseudo) Create project and items, then JS reorder as in tutorial
    assert true
  end
end
```

## 23) Monitoring & Health (Kamal, /up, logs, metrics)

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  allow_unauthenticated_access only: :show
  def show
    ActiveRecord::Base.connection.execute("select 1")
    Rails.cache.fetch([:health, :ping]) { Time.current.to_i }
    render plain: "OK"
  end
end
```

```bash
# Dockerfile healthcheck
HEALTHCHECK --interval=30s --timeout=3s CMD curl -fsS http://localhost:3000/up || exit 1
```

## Appendix: Kamal Deploy (DigitalOcean)

```dockerfile
FROM ruby:3.3
RUN apt-get update -y && apt-get install -y build-essential libvips curl
WORKDIR /rails
ENV RAILS_ENV=production
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test
COPY . .
RUN bin/rails assets:precompile
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD curl -fsS http://localhost:3000/up || exit 1
CMD ["bin/rails","server","-b","0.0.0.0","-p","3000"]
```

```yaml
# config/deploy.yml (example)
service: signalboard
image: registry.digitalocean.com/YOUR_REGISTRY/signalboard
servers:
  - YOUR_DROPLET_IP
registry:
  server: registry.digitalocean.com
  username: YOUR_DO_USERNAME
  password:
    - DOCKER_REGISTRY_TOKEN
env:
  clear:
    RAILS_LOG_TO_STDOUT: "1"
    RAILS_SERVE_STATIC_FILES: "true"
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
ssh:
  user: root
  keys: [~/.ssh/id_rsa]
```

```bash
doctl registry login
bundle add kamal
bin/kamal init
bin/kamal env push
bin/kamal deploy
```
