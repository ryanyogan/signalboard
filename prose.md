# Rails 8 “Signalboard” — The Book (Feature Request Board with TUI UI)

This is the **prose-first** edition of the tutorial. It’s written like a book: you’ll see
commands and code, but most of the words are dedicated to **teaching** the “what” and **why**
behind each decision. It spans all **23 chapters** from `rails new` to **Kamal deploy**,
including **Solid Queue/Cache/Cable**, **built-in authentication**, **Turbo 8**, **Stimulus**,
**Tailwind**, **notifications**, **recurring jobs**, **tests**, and **monitoring**.

## 1) What You’re Building & Why Rails 8

We’re building **Signalboard**, a **Feature Request Board** for one or more projects. Users can
log in, post requests, vote, comment, and watch changes propagate in **real-time**. We use a web
**TUI** (terminal-like) visual style because it’s: minimal, clean, and surprisingly readable.

**Why Rails 8?** Because it rolls the platform into the framework:

- **Solid Queue** replaces a separate job system and extra infra.
- **Solid Cache** removes the need for a cache server in many apps.
- **Solid Cable** gives us websockets without Redis in production.
- **Built-in auth** saves you from pulling in Devise and its learning curve.
- **Kamal** turns deploy into a few commands.

Result: fewer moving parts, more shipping.

## 2) Environment & Philosophy

We’ll target **Ruby 3.3+** and **Rails 8**. SQLite for dev (zero setup), and Tailwind via the
`tailwindcss-rails` gem (no Node bundler necessary). You can switch to esbuild or Vite later if
you prefer, but we’ll stay with **importmap** to keep it light.

Principles we’ll follow:

- **Ship small slices**: every chapter leaves the app working.
- **Server-driven UI**: Turbo Streams/Frames and modest Stimulus controllers.
- **Real-time first**: keep users in sync without page refreshes.

```bash
ruby -v
gem install rails
rails -v
```

If `rails -v` shows **8.x**, you’re good.

## 3) New App & First Run

We generate the app with Tailwind and SQLite. Importmap is default in Rails 8 and is perfect for
our needs here.

```bash
rails new signalboard --css=tailwind --database=sqlite3
cd signalboard
bin/setup
bin/dev
```

**What just happened?**

- `--css=tailwind` wires Tailwind with Rails’ asset story.
- **Propshaft** serves assets, digests filenames, and keeps things simple.
- **Importmap** pulls Turbo/Stimulus as URL-pinned modules—no bundling step.
- `bin/dev` runs the Tailwind watcher and Rails server together.

## 4) Built-in Authentication — The Rails 8 Way

Rails 8 ships a built-in **Authentication** generator. It creates `User`, `Session`, controllers,
views, and a password reset flow. We add a tiny **RegistrationsController** so people can sign up.

```bash
bin/rails generate authentication
bin/rails db:migrate
```

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

  def new
    @user = User.new
  end

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

**Why store a session token in a signed cookie?** It’s simple, fast, and revocable. You can end a
session server-side by deleting the corresponding DB session row, invalidating the cookie.

## 5) TUI Layout with Tailwind

A good layout is a force multiplier. We pick a **monospace** font and minimal color to create a
web **TUI** aesthetic. The goal is strong contrast, easy scanning, and little ceremony.

```erb
<!-- app/views/layouts/application.html.erb (key ideas only) -->
<meta name="view-transition" content="same-origin">
<meta name="turbo-refresh-method" content="morph">
<meta name="turbo-refresh-scroll" content="preserve">
```

- The **Turbo 8** meta tags turn on view transitions and morphing, so page-to-page feels smooth.
- We’ll add a subtle CRT scanline overlay for the TUI vibe (later chapters show the CSS).

## 6) Data Model — Keep It Obvious

We’ll model six concepts:

- **User** — who signs in.
- **Project** — container for features.
- **FeatureRequest** — the core item (title, body, status, position).
- **Comment** — discussion on a feature.
- **Vote** — user upvotes a feature (1/user).
- **Subscription** — user follows a project to get notifications.
- **Notification** — in-app badge + list for comments/status changes.

```bash
bin/rails g model Project name:string description:text
bin/rails g model FeatureRequest project:references user:references title:string body:text status:string:index position:integer:index
bin/rails g model Comment feature_request:references user:references body:text
bin/rails g model Vote feature_request:references user:references
bin/rails g model Subscription project:references user:references
bin/rails g model Notification user:references notifiable:references{polymorphic} kind:string read_at:datetime
bin/rails db:migrate
```

**Why `polymorphic` notifications?** So the same table can reference different events (comments,
status changes) without extra tables.

## 7) Routes & Controllers — A Thin, Friendly Layer

We nest `feature_requests` under `projects` because requests live in a project. `comments` and
`votes` live under a specific `feature_request`. A custom `reorder` collection route will persist
drag-and-drop ordering for the list.

```ruby
# config/routes.rb (core idea)
root "projects#index"
resources :projects do
  resources :feature_requests do
    collection { post :reorder }
    resources :comments, only: [:create, :destroy]
    resources :votes,    only: [:create, :destroy]
  end
  resources :subscriptions, only: [:create, :destroy]
end
resources :notifications, only: [:index] do
  collection { post :mark_all_read }
end
get "/up", to: "health#show"
```

**Why keep controllers thin?** So your domain logic lives in models and helpers, making it easier to
test and reuse.

## 8) Views with Turbo 8 — Streams & Frames

For the index list and comments, we’ll render **Turbo Streams** so new items appear in real-time.
For focused sub-updates, we’ll use **Frames**. The mental model: the server renders HTML; Turbo
smartly patches the page.

## 9) Solid Cable — Unread Notifications Badge in Real-time

We’ll add a `NotificationsChannel` that streams an **unread count** to the header badge. When a
notification is created or marked read, the channel pushes the new count to the user.

## 10) In-app Notifications — Turbo Streams Replace the List

A `/notifications` page lists the most recent 50. A 'mark all read' button flips `read_at` and
the header badge updates via the channel. The list itself can be re-rendered via Turbo Stream.

## 11) Email & Daily Digest — Action Mailer + Solid Queue

We send a daily digest of recent feature request activity for the projects a user follows. One job
enqueues **per user**, and a scheduler job enqueues those **per-user** jobs.

## 12) Recurring Jobs — `config/recurring.yml`

Solid Queue’s scheduler reads `config/recurring.yml`. When it sees our cron, it enqueues the
digest-enqueue job at the right time. This keeps the app self-contained (no cron daemon to manage).

## 13) Solid Cache — Fast Project Stats

We store a small hash per project (counts by status). Any change to a feature request busts the
cache key. That makes the sidebar stats instant without stale data.

## 14) Stimulus — Lightweight Interactivity

We write small controllers for optimistic form submission states, clipboard copy, and toasts.
**Each controller does one thing** and is trivial to debug.

## 15) Stimulus Advanced — Drag-and-Drop Reordering

We implement HTML5 DnD without a dependency. The DOM reorders **optimistically**; the server
persists positions; a Turbo Stream re-renders the list as the source of truth.

## 16) Live Search & Filter — Turbo Frames or URL replace

We debounce keystrokes in a Stimulus controller and update the URL’s querystring. Turbo replaces
the list in-place, keeping history clean.

## 17) Theme Switcher — TUI Night/Day

We toggle a CSS custom property that controls the CRT scanline/glow intensity. Simple, playful,
and no global re-render.

## 18) Security & Hardening

Keep Rails’ defaults (CSRF, strong params) and add a CSP. Consider **Rack::Attack** for
rate-limiting session attempts. Use `secure` cookies in production.

## 19) Production Configuration

Use `bin/rails credentials:edit` for secrets. Configure SMTP. In `config/cable.yml` set `production`’s
adapter to `solid_cable`. Prefer DO Managed Postgres and set `DATABASE_URL`.

## 20) Testing with Minitest — Models, Jobs, Channels, System

- **Model tests** ensure validations and callbacks hold.

- **Job tests** assert enqueues (ActiveJob intercepts enqueues in test).

- **Channel tests** confirm subscriptions/streams.

- **System tests** drive a real browser (headless Chrome) to click through Turbo flows.

## 21) Recurring Jobs Deep Dive

Run a **single scheduler** in production (usually part of the worker). Separate queues and set
concurrency to avoid job starvation. Use time helpers like `travel_to` to test cron windows.

## 22) Drag-and-Drop System Test & Edge Cases

Simulating drag events is flaky in Selenium, so we reorder the DOM and `POST` the new sequence from
JS in the test. On the server, validate that all IDs belong to the current project before updating.

## 23) Monitoring & Health — /up, logs, and a simple gauge

Expose `/up` for Kamal’s `HEALTHCHECK`. Add minimal structured logs (Lograge) and a `/metrics`
endpoint (a simple gauge is fine to start). You can add `prometheus-client` later if you want full
histograms/counters.

## Appendix — Kamal Deploy (DigitalOcean)

Provision a DO droplet, set up DO Container Registry (or use Docker Hub), and follow `bin/kamal init`.
Put `RAILS_MASTER_KEY` and `DATABASE_URL` in Kamal secrets. Deploy with `bin/kamal deploy` and
tail logs with `bin/kamal app logs -f`.
