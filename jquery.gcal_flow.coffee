$ = jQuery

if window? and window._gCalFlow_debug? and console?
  log = console
  log.debug ?= log.log
else
  log = {}
  log.error = log.warn = log.log = log.info = log.debug = ->

pad_zero = (num, size = 2) ->
  if 10 * (size-1) < num then return num
  ret = ""
  for i in [1..(size-"#{num}".length)]
    ret += "0"
  ret + num

base_obj =
  target: null
  template: $("""<div class="gCalFlow">
      <div class="gcf-header-block">
        <div class="gcf-title-block">
          <span class="gcf-title"></span>
        </div>
      </div>
      <div class="gcf-item-container-block">
        <div class="gcf-item-block">
          <div class="gcf-item-header-block">
            <div class="gcf-item-date-block">
              [<span class="gcf-item-date"></span>]
            </div>
            <div class="gcf-item-title-block">
              <strong class="gcf-item-title"></strong>
            </div>
          </div>
          <div class="gcf-item-body-block">
            <div class="gcf-item-description">
            </div>
          </div>
        </div>
      </div>
      <div class="gcf-last-update-block">
        LastUpdate: <span class="gcf-last-update"></span>
      </div>
    </div>""")
  opts: {
    maxitem: 15
    calid: null
    mode: 'upcoming'
    feed_url: null
    auto_scroll: true
    scroll_interval: 10 * 1000
    date_formatter: (d, allday_p) ->
      `if (allday_p) {` # why??????
      return "#{d.getFullYear()}-#{pad_zero d.getMonth()+1}-#{pad_zero d.getDate()}"
      `} else {`
      return "#{d.getFullYear()}-#{pad_zero d.getMonth()+1}-#{pad_zero d.getDate()} #{pad_zero d.getHours()}:#{pad_zero d.getMinutes()}"
      `}`
  }

  update_opts: (new_opts) ->
    log.debug "update_opts was called"
    log.debug "old options:", this.opts
    this.opts = $.extend({}, this.opts, new_opts)
    log.debug "new options:", this.opts

  gcal_url: ->
    if !this.opts.calid && !this.opts.feed_url
      log.error "Option calid and feed_url are missing. Abort URL generation"
      this.target.text("Error: You need to set 'calid' or 'feed_url' option.")
      throw "gCalFlow: calid and feed_url missing"
    if this.opts.feed_url
      this.opts.feed_url
    else if this.opts.mode == 'updates'
      "https://www.google.com/calendar/feeds/#{this.opts.calid}/public/full?alt=json-in-script&max-results=#{this.opts.maxitem}&orderby=lastmodified&sortorder=descending"
    else
      "https://www.google.com/calendar/feeds/#{this.opts.calid}/public/full?alt=json-in-script&max-results=#{this.opts.maxitem}&orderby=starttime&futureevents=true&sortorder=ascending&singleevents=true"

  fetch: ->
    log.debug "Starting ajax call for #{this.gcal_url()}"
    self = this
    success_handler = (data) ->
      log.debug "Ajax call success. Response data:", data
      self.render_data(data, this)
    $.ajax {
      success:  success_handler
      dataType: "jsonp"
      url: this.gcal_url()
    }

  parse_date: (dstr) ->
    di = Date.parse dstr
    if !di
      d = dstr.split('T')
      dinfo = $.merge d[0].split('-'), if d[1] then d[1].split(':')[0..1] else []
      eval "new Date(#{dinfo.join(',')});"
    else
      new Date(di)


  render_data: (data) ->
    log.debug "start rendering for data:", data
    feed = data.feed
    t = this.template.clone()

    titlelink = this.opts.titlelink ? "http://www.google.com/calendar/embed?src=#{this.opts.calid}"
    t.find('.gcf-title').html $("<a />").attr({target: '_blank', href: titlelink}).text feed.title.$t
    t.find('.gcf-last-update').text this.opts.date_formatter this.parse_date feed.updated.$t

    it = t.find('.gcf-item-block')
    it.detach()
    it = $(it[0])
    log.debug "item block template:", it
    items = $()
    log.debug "render entries:", feed.entry
    for ent in feed.entry[0..this.opts.maxitem]
      log.debug "formatting entry:", ent
      ci = it.clone()
      `if (ent.gd$when) {` # hmmmmmmmmmmmm, why I get syntax error when use if in coffee syntax????
      st = ent.gd$when[0].startTime
      idate = this.opts.date_formatter this.parse_date(st), st.indexOf('T') < 0
      ci.find('.gcf-item-date').text idate
      `}`
      ci.find('.gcf-item-title').html $('<a />').attr({target: '_blank', href: ent.link[0].href}).text ent.title.$t
      ci.find('.gcf-item-description').text ent.content.$t
      log.debug "formatted item entry:", ci[0]
      items.push ci[0]

    log.debug "formatted item entry array:", items
    ic = t.find('.gcf-item-container-block')
    log.debug "item container element:", ic
    ic.html(items)

    this.target.html(t.html())
    scroll_container = this.target.find('.gcf-item-container-block')
    scroll_children = scroll_container.find(".gcf-item-block")
    log.debug "scroll container:", scroll_container
    `if (this.opts.auto_scroll && scroll_container.size() > 0 && scroll_children.size() > 1) { ` # ???????? sigh.....
    state = {idx: 0}
    scroller = ->
      log.debug "current scroll position:", scroll_container.scrollTop()
      log.debug "scroll capacity:", scroll_container[0].scrollHeight - scroll_container[0].clientHeight
      `if (scroll_container.scrollTop() >= scroll_container[0].scrollHeight - scroll_container[0].clientHeight) {`
      log.debug "scroll to top"
      state.idx = 0
      scroll_container.animate {scrollTop: scroll_children[0].offsetTop}
      `} else {`
      scroll_to = scroll_children[state.idx].offsetTop
      log.debug "scroll to #{scroll_to}px"
      scroll_container.animate {scrollTop: scroll_to}
      state.idx += 1
      `}`
    scroll_timer = setInterval scroller, this.opts.scroll_interval
    `}`

createInstance = (target, opts) ->
  F = ->
  F.prototype = base_obj
  obj = new F()
  obj.target = target
  target.addClass('gCalFlow')
  if target.children().size() > 0
    log.debug "Target node has children, use target element as template."
    obj.template = target
  obj.update_opts(opts)
  obj

methods =
  init: (opts = {}) ->
    data = this.data('gCalFlow')
    if !data then this.data 'gCalFlow', { target: this, obj: createInstance(this, opts) }

  destroy: ->
    data = this.data('gCalFlow')
    data.obj.target = null
    $(window).unbind('.gCalFlow')
    data.gCalFlow.remove()
    this.removeData('gCalFlow')

  render: ->
    data = this.data('gCalFlow')
    self = data.obj
    self.fetch()

      
$.fn.gCalFlow = (method) ->
  orig_args = arguments
  if typeof method == 'object' || !method
    this.each ->
      methods.init.apply $(this), orig_args
      methods.render.apply $(this), orig_args
  else if methods[method]
    this.each ->
      methods[method].apply $(this), Array.prototype.slice.call(orig_args, 1)
  else if method == 'version'
    "1.0.0"
  else
    $.error "Method #{method} dose not exist on jQuery.gCalFlow"