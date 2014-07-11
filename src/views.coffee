define 'app/views', ['underscore', 'backbone', 'backbone.marionette', 'leaflet', 'i18next', 'moment', 'app/p13n', 'app/widgets', 'app/jade', 'app/models', 'app/search', 'app/color', 'app/draw', 'app/transit', 'app/animations', 'app/accessibility', 'app/sidebar-region'], (_, Backbone, Marionette, Leaflet, i18n, moment, p13n, widgets, jade, models, search, colors, draw, transit, animations, accessibility, SidebarRegion) ->

    PAGE_SIZE = 200

    mixOf = (base, mixins...) ->
        class Mixed extends base
        for mixin in mixins by -1 #earlier mixins override later ones
            for name, method of mixin::
                Mixed::[name] = method
        Mixed

    class SMTemplateMixin
        mixinTemplateHelpers: (data) ->
            jade.mixin_helpers data
            return data
        getTemplate: ->
            return jade.get_template @template

    class SMItemView extends mixOf Marionette.ItemView, SMTemplateMixin
    class SMCollectionView extends mixOf Marionette.CollectionView, SMTemplateMixin
    class SMCompositeView extends mixOf Marionette.CompositeView, SMTemplateMixin
    class SMLayout extends mixOf Marionette.Layout, SMTemplateMixin

    class TitleView extends SMItemView
        className:
            'title-control'
        render: =>
            @el.innerHTML = jade.template 'title-view', lang: p13n.get_language()

    class LandingTitleView extends SMItemView
        template: 'landing-title-view'
        id: 'title'
        className: 'landing-title-control'
        initialize: ->
            @listenTo(app.vent, 'title-view:hide', @hideTitleView)
            @listenTo(app.vent, 'title-view:show', @unHideTitleView)
        serializeData: ->
            isHidden: @isHidden
            lang: p13n.get_language()
        hideTitleView: ->
            $('body').removeClass 'landing'
            @isHidden = true
            @render()
        unHideTitleView: ->
            $('body').addClass 'landing'
            @isHidden = false
            @render()

    class BrowseButtonView extends SMItemView
        template: 'navigation-browse'
    class SearchInputView extends SMItemView
        classname: 'search-input-element'
        template: 'navigation-search'
        events:
            'typeahead:selected': 'autosuggest_show_details'
            # Important! The following ensures the click
            # will only cause the intended typeahead selection.
            'click .tt-suggestion': (e) -> e.stopPropagation()
        onRender: () ->
            @enable_typeahead('input.form-control[type=search]')
        enable_typeahead: (selector) ->
            search_el = @$el.find selector
            service_dataset =
                source: search.servicemap_engine.ttAdapter(),
                displayKey: (c) -> c.name[p13n.get_language()]
                templates:
                    empty: (ctx) -> jade.template 'typeahead-no-results', ctx
                    suggestion: (ctx) -> jade.template 'typeahead-suggestion', ctx
            event_dataset =
                source: search.linkedevents_engine.ttAdapter(),
                displayKey: (c) -> c.name[p13n.get_language()]
                templates:
                    empty: ''
                    suggestion: (ctx) -> jade.template 'typeahead-suggestion', ctx

            search_el.typeahead null, [service_dataset, event_dataset]

            # On enter: was there a selection from the autosuggestions
            # or did the user hit enter without having selected a
            # suggestion?
            selected = false
            search_el.on 'typeahead:selected', (ev) =>
                selected = true
            search_el.keyup (ev) =>
                # Handle enter
                if ev.keyCode != 13
                    return
                search_el.typeahead 'close'
                if selected
                    selected = false
                    return
                query = $.trim search_el.val()
                app.commands.execute 'search', query
            search_el.on 'typeahead:opened', (ev) =>
                app.commands.execute 'clearSearch'
        autosuggest_show_details: (ev, data, _) ->
            # Remove focus from the search box to hide keyboards on touch devices.
            $('.search-container input').blur()
            model = null
            object_type = data.object_type
            switch object_type
                when 'unit'
                    model = new models.Unit(data)
                    app.commands.execute 'setUnit', model
                    app.commands.execute 'selectUnit', model
                when 'service'
                    app.commands.execute 'addService',
                        new models.Service(data)
                when 'event'
                    app.commands.execute 'selectEvent',
                        new models.Event(data)

    class NavigationHeaderView extends SMLayout
        # This view is responsible for rendering the navigation
        # header which allows the user to switch between searching
        # and browsing. Since the search bar is part of the header,
        # this view also handles search input.
        className: 'container'
        template: 'navigation-header'
        regions:
            search: '#search-region'
            browse: '#browse-region'
        events:
            'click .header': 'open'
            'click .close-button': 'close'
        initialize: (options) ->
            @navigation_layout = options.layout
        onShow: ->
            @search.show new SearchInputView()
            @browse.show new BrowseButtonView()
        open: (event) ->
            action_type = $(event.currentTarget).data('type')
            @update_classes action_type
            if action_type is 'search'
                @$el.find('input').select()
            @navigation_layout.open_view_type = action_type
            @navigation_layout.change action_type
        close: (event) ->
            event.preventDefault()
            event.stopPropagation()
            header_type = $(event.target).closest('.header').data('type')
            @update_classes null

            # Clear search query if search is closed.
            if header_type is 'search'
                @$el.find('input').val('')
            @navigation_layout.change()
        update_classes: (opening) ->
            classname = "#{opening}-open"
            if @$el.hasClass classname
                return
            @$el.removeClass().addClass('container')
            if opening?
                @$el.addClass classname

    class NavigationLayout extends SMLayout
        className: 'service-sidebar'
        template: 'navigation-layout'
        regionType: SidebarRegion
        regions:
            header: '#navigation-header'
            contents: '#navigation-contents'
        onShow: ->
            @header.show new NavigationHeaderView
                layout: this
        initialize: (options) ->
            @service_tree_collection = options.service_tree_collection
            @selected_services = options.selected_services
            @search_results = options.search_results
            @selected_units = options.selected_units
            @selected_events = options.selected_events
            @breadcrumbs = [] # for service-tree view
            @open_view_type = null # initially the sidebar is closed.
            @add_listeners()
        add_listeners: ->
            @listenTo @search_results, 'reset', ->
                @change 'search'

            @listenTo @service_tree_collection, 'sync', ->
                #console.log 'LISTENED SERVICE TREE COLLECTION SYNC!'
                @change 'browse'
            @listenTo @selected_services, 'reset', ->
                #console.log 'LISTENED SELECTED SERVICES RESET!'
                @change 'browse'

            @listenTo @selected_units, 'reset', (unit, coll, opts) ->
                unless @selected_units.isEmpty()
                    @change 'details'
            @listenTo @selected_units, 'remove', (unit, coll, opts) ->
                @change null

            @listenTo @selected_events, 'reset', (unit, coll, opts) ->
                unless @selected_events.isEmpty()
                    @change 'event'
            @listenTo @selected_events, 'remove', (unit, coll, opts) ->
                @change null

            $(window).resize( =>
                @contents.currentView?.set_max_height?()
            )
        right_edge_coordinate: ->
            if @opened
                @$el.offset().left + @$el.outerWidth()
            else
                0
        get_animation_type: (new_type) ->
            animation_type = null
            current_type = @contents.currentView?.type
            console.log 'current_type', current_type
            if current_type
                switch current_type
                    when 'event'
                        animation_type = 'right'
                    when 'details'
                        switch new_type
                            when 'event' then animation_type = 'left'
                            when 'details' then animation_type = 'up-and-down'
                            else animation_type = 'right'
                    when 'service-tree'
                        animation_type = @contents.currentView.animation_type or 'left'
                        console.log 'was service tree animation: ', animation_type
            console.log 'animation_type', animation_type
            return animation_type

        change: (type) ->
            if type is null
                type = @back
            console.log '\n\ntype', type
            console.log '@open_view_type', @open_view_type

            # Do not render a view that is not open in the sidebar.
            #return if type? and type != @open_view_type

            # Do not render browse if it's not open
            #return if type == 'browse' and @open_view_type != 'browse'

            switch type
                when 'browse'
                    view = new ServiceTreeView
                        collection: @service_tree_collection
                        selected_services: @selected_services
                        breadcrumbs: @breadcrumbs
                    @back = 'browse'
                when 'search'
                    view = new SearchResultsView
                        collection: @search_results
                    unless @search_results.isEmpty()
                        @back = 'search'
                when 'details'
                    view = new DetailsView
                        model: @selected_units.first()
                        back: @back
                when 'event'
                    view = new EventView
                        model: @selected_events.first()
                else
                    @back = null
                    @opened = false
                    view = null
                    console.log 'CLOSE DOWN THE VIEW IN CONTENTS!'
                    @contents.close()

            if view?
                # todo: animations
                #console.log '@contents.currentView ------->', @contents.currentView
                @contents.show view, {animation_type: @get_animation_type(type)}
                @opened = true
                #if type == 'browse'
                    # downwards reveal anim
                    # todo: upwards hide

                    # Handle all sidebar animations in sidebar-region and animations.coffee
                    # view.set_max_height 0
                    # view.set_max_height()

                # This needs to be done in the animation callback.
                # if type == 'details' or type == 'event'
                #     view.set_max_height()

    # class LegSummaryView extends SMItemView
    # TODO: use this instead of hardcoded template
    # in routingsummaryview
    #     template: 'routing-leg-summary'
    #     tagName: 'span'
    #     className: 'icon-icon-public-transport'

    class RoutingSummaryView extends SMItemView
        #itemView: LegSummaryView
        #itemViewContainer: '#route-details'
        template: 'routing-summary'
        className: 'route-summary'
        events:
            'click .route-selector a': 'switch_itinerary'
            'click .switch-end-points': 'switch_end_points'
            'click .accessibility-viewpoint': 'set_accessibility'


        NUMBER_OF_CHOICES_SHOWN = 3

        LEG_MODES = {
            'WALK': {
                icon: 'icon-icon-by-foot',
                color_class: 'transit-default',
                text: i18n.t('transit.walk')
            }
            'BUS': {
                icon: 'icon-icon-bus',
                color_class: 'transit-default',
                text: i18n.t('transit.bus')
            }
            'TRAM': {
                icon: 'icon-icon-tram',
                color_class: 'transit-tram',
                text: i18n.t('transit.tram')
            }
            'SUBWAY': {
                icon: 'icon-icon-subway',
                color_class: 'transit-subway',
                text: i18n.t('transit.subway')
            }
            'RAIL': {
                icon: 'icon-icon-train',
                color_class: 'transit-rail',
                text: i18n.t('transit.rail')
            }
            'FERRY': {
                icon: 'icon-icon-public-transport',
                color_class: 'transit-ferry',
                text: i18n.t('transit.ferry')
            }
            'WAIT': {
                icon: '',
                color_class: 'transit-default',
                text: i18n.t('transit.wait')
            }
        }

        STEP_DIRECTIONS = {
            'DEPART': 'Depart from '
            'CONTINUE': 'Continue on '
            'RIGHT': 'Turn right to '
            'LEFT': 'Turn left to '
            'SLIGHTLY_RIGHT': 'Turn slightly right to '
            'SLIGHTLY_LEFT': 'Turn slightly left to '
            'HARD_RIGHT': 'Turn right hard to '
            'HARD_LEFT': 'Turn left hard to '
            'UTURN_RIGHT': 'U-turn right to '
            'UTURN_LEFT': 'U-turn left to '
        }

        initialize: (options) ->
            @to_address = options.to_address
            @selected_itinerary_index = 0
            @itinery_choices_start_index = 0
            @details_open = false

        serializeData: ->
            window.debug_route = @model

            itinerary = @model.plan.itineraries[@selected_itinerary_index]
            filtered_legs = _.filter(itinerary.legs, (leg) -> leg.mode != 'WAIT')

            legs = _.map(filtered_legs, (leg) =>
                start_time: moment(leg.startTime).format('LT')
                start_location: leg.from.name
                distance: (leg.distance / 1000).toFixed(1) + 'km'
                icon: LEG_MODES[leg.mode].icon
                transit_color_class: LEG_MODES[leg.mode].color_class
                transit_mode: LEG_MODES[leg.mode].text
                transit_details: @get_transit_details leg
                route: if leg.route.length < 5 then leg.route else ''
                steps: @parse_steps leg
            )

            end = {
                time: moment(itinerary.endTime).format('LT')
                name: @model.plan.to.name
                address: p13n.get_translated_attr(@to_address)
            }

            route = {
                duration: Math.round(itinerary.duration / 60) + ' min'
                walk_distance: (itinerary.walkDistance / 1000).toFixed(1) + 'km'
                legs: legs
                end: end
            }

            return {
                itinerary: route
                itinerary_choices: @get_itinerary_choices()
                selected_itinerary_index: @selected_itinerary_index
                details_open: @details_open
                current_time: moment(new Date()).format('YYYY-MM-DDTHH:mm')
            }

        parse_steps: (leg) ->
            steps = []
            if leg.mode == 'WALK'
                for step in leg.steps
                    text = ''
                    if step.relativeDirection of STEP_DIRECTIONS
                        text += STEP_DIRECTIONS[step.relativeDirection]
                    else
                        text += step.relativeDirection + ' '
                    text += step.streetName
                    steps.push(text)
            else
                steps.push('Stop list not available')
            return steps

        get_transit_details: (leg) ->
            if leg.mode == 'SUBWAY'
                return "(#{i18n.t('transit.toward')} #{leg.headsign})"
            else
                return ''

        get_itinerary_choices: ->
            number_of_itineraries = @model.plan.itineraries.length
            start = @itinery_choices_start_index
            stop = Math.min(start + NUMBER_OF_CHOICES_SHOWN, number_of_itineraries)
            return _.range(start, stop)

        switch_itinerary: (event) ->
            event.preventDefault()
            @selected_itinerary_index = $(event.target).data('index')
            @details_open = true
            @render()

        switch_end_points: (event) ->
            event.preventDefault()
            # Add switching start and end points functionality here.

        set_accessibility: (event) ->
            event.preventDefault()
            # Add personalisation view opening here.

    class EventListRowView extends SMItemView
        tagName: 'li'
        template: 'event-list-row'
        events:
            'click .show-event-details': 'show_event_details'

        serializeData: ->
            start_time = @model.get 'start_time'
            # Show time only if it's available.
            time = ''
            if start_time.split('T').length > 1
                time = moment(start_time).format('LT')

            name: p13n.get_translated_attr(@model.get 'name')
            date: p13n.get_humanized_date(start_time)
            time: time
            info_url: p13n.get_translated_attr(@model.get 'info_url')

        show_event_details: (event) ->
            event.preventDefault()
            app.commands.execute 'selectEvent', @model

    class EventListView extends SMCollectionView
        tagName: 'ul'
        className: 'events'
        itemView: EventListRowView
        initialize: (opts) ->
            @parent = opts.parent


    class EventView extends SMLayout
        id: 'event-view-container'
        template: 'event'
        events:
            'click .back-button': 'go_back'
            'click .sp-name a': 'go_back'
        type: 'event'

        initialize: (options) ->
            @embedded = options.embedded
            @service_point = @model.get('unit')

        serializeData: ->
            data = @model.toJSON()
            data.embedded_mode = @embedded
            data.time = moment(@model.get 'start_time').format('LLLL')
            if @service_point?
                data.sp_name = @service_point.get 'name'
                data.sp_url = @service_point.get 'www_url'
                data.sp_phone = @service_point.get 'phone'
            else
                data.sp_name = @model.get('location_extra_info')
                data.prevent_back = true
            data

        go_back: (event) ->
            event.preventDefault()
            app.commands.execute 'clearSelectedEvent'
            app.commands.execute 'selectUnit', @service_point

        set_max_height: () ->
            # Set the event view content max height for proper scrolling.
            # Must be called after the view has been inserted to DOM.
            max_height = $(window).innerHeight() - @$el.find('.content').offset().top
            @$el.find('.content').css 'max-height': max_height


    class DetailsView extends SMLayout
        id: 'details-view-container'
        template: 'details'
        regions:
            'routing_region': '.route-navigation'
            'events_region': '.event-list'
        events:
            'click .back-button': 'user_close'
            'click .icon-icon-close': 'user_close'
            'click .show-more-events': 'show_more_events'
            'click .disabled': 'prevent_disabled_click'
            'click .set-accessibility-profile': 'set_accessibility_profile'
            'click .leave-feedback': 'leave_feedback_on_accessibility'
        type: 'details'

        initialize: (options) ->
            @INITIAL_NUMBER_OF_EVENTS = 5
            @NUMBER_OF_EVENTS_FETCHED = 20
            @embedded = options.embedded
            @back = options.back
            # We need to save the content that was in the navigations-contents before render.
            #@$old_content = $('#navigation-contents').children().first()
            #debugger

        render: ->
            super()
            marker_canvas = @$el.find('#details-marker-canvas').get(0)
            context = marker_canvas.getContext('2d')
            size = 40
            color = app.color_matcher.unit_color(@model) or 'rgb(0, 0, 0)'
            id = 0
            rotation = 90

            marker = new draw.Plant size, color, id, rotation
            marker.draw context

        onRender: ->
            # Events
            #
            if @model.event_list.isEmpty()
                @listenTo @model.event_list, 'reset', (list) =>
                    @update_events_ui(list.fetchState)
                    @render_events(list)
                @model.event_list.pageSize = @INITIAL_NUMBER_OF_EVENTS
                @model.get_events()
                @model.event_list.pageSize = @NUMBER_OF_EVENTS_FETCHED
            else
                @update_events_ui(@model.event_list.fetchState)
                @render_events(@model.event_list)

            # Route planning
            #
            last_pos = p13n.get_last_position()
            if not last_pos
                @listenTo p13n, 'position', (pos) ->
                    @request_route pos.coords
                p13n.request_location()
            else
                @request_route last_pos.coords

        update_events_ui: (fetchState) =>
            $events_section = @$el.find('.events-section')

            # Update events section short text count.
            if fetchState.count
                short_text = i18n.t('sidebar.event_count', {count: fetchState.count})
            else
                # Handle no events -cases.
                short_text = i18n.t('sidebar.no_events')
                @$('.show-more-events').hide()
                $events_section.find('.collapser').addClass('disabled')
            $events_section.find('.short-text').text(short_text)

            # Remove show more button if all events are visible.
            if !fetchState.next and @model.event_list.length == @events_region.currentView?.collection.length
                @$('.show-more-events').hide()

        user_close: (event) ->
            app.commands.execute 'clearSelectedUnit'

        prevent_disabled_click: (event) ->
            event.preventDefault()
            event.stopPropagation()

        set_max_height: () ->
            # Set the details view content max height for proper scrolling.
            # Must be called after the view has been inserted to DOM.
            max_height = $(window).innerHeight() - @$el.find('.content').offset().top
            @$el.find('.content').css 'max-height': max_height

        get_translated_provider: (provider_type) ->
            SUPPORTED_PROVIDER_TYPES = [101, 102, 103, 104, 105]
            if provider_type in SUPPORTED_PROVIDER_TYPES
                i18n.t("sidebar.provider_type.#{ provider_type }")
            else
                ''

        serializeData: ->
            embedded = @embedded
            data = @model.toJSON()
            data.provider = @get_translated_provider(@model.get('provider_type'))
            description = data.description
            if @back?
                data.back_to = i18n.t('sidebar.back_to.' + @back)
            MAX_LENGTH = 20
            if description
                words = description.split /[ ]+/
                if words.length > MAX_LENGTH + 1
                    data.description = words[0..MAX_LENGTH].join(' ') + '&hellip;'
            data.embedded_mode = embedded
            data.accessibility = @get_accessibility_data()
            data

        get_accessibility_data: ->
            has_data = @model.get('accessibility_properties')?.length
            # TODO: Check if accessibility profile is set once that data is available.
            profile_set = false
            shortcomings = []
            details = []
            header_classes = ''
            short_text = ''

            if has_data
                shortcomings = accessibility.get_shortcomings @model.get('accessibility_properties'), 1
                # TODO: Fetch real details here once the data is available.
                details = [
                    'Lorem ipsum dolor sit amet, eros honestatis ullamcorper ut vel, eum cu.'
                    'purto decore, mea te errem regione. Mei cu utamur tacimates consetetur.'
                    'paulo soleat maiorum vim ne. Ea vim liber euripidis voluptatibus, eam.'
                    'cu etiam sapientem imperdiet. Quo sint pertinacia conclusionemque ut.'
                    'Ea pro autem appellantur, usu ne illum suscipit. Ex mei detracto.'
                ]

            if has_data and profile_set
                if shortcomings.length
                    header_classes = 'has-shortcomings'
                    short_text = i18n.t('accessibility.shortcoming_count', {count: shortcomings.length})
                else
                    header_classes += 'no-shortcomings'
                    short_text = i18n.t('accessibility.no_shortcomings')
            else if profile_set
                short_text = i18n.t('accessibility.no_data')

            profile_set: profile_set
            profile_icon: 'icon-icon-wheelchair'
            profile_text: i18n.t('accessibility.profile_text.wheelchair')
            shortcomings: shortcomings
            details: details
            feedback: @get_dummy_feedback()
            header_classes: header_classes
            short_text: short_text
            has_data: has_data

        get_dummy_feedback: ->
            now = new Date()
            yesterday = new Date(now.setDate(now.getDate() - 1))
            last_month = new Date(now.setMonth(now.getMonth() - 1))
            feedback = []
            feedback.push(
                time: moment(yesterday).calendar()
                profile: 'wheelchair user.'
                header: 'The ramp is too steep'
                content: "The ramp is just bad! It's not connected to the entrance stand out clearly. Outside the door there is sufficient room for moving e.g. with a wheelchair. The door opens easily manually."
            )
            feedback.push(
                time: moment(last_month).calendar()
                profile: 'rollator user'
                header: 'Not accessible at all and the staff are unhelpful!!!!'
                content: "The ramp is just bad! It's not connected to the entrance stand out clearly. Outside the door there is sufficient room for moving e.g. with a wheelchair. The door opens easily manually."
            )

            feedback

        set_accessibility_profile: (event) ->
            event.preventDefault()
            # TODO: Open accessibility settings here once accessibility profile is ready.

        leave_feedback_on_accessibility: (event) ->
            event.preventDefault()
            # TODO: Add here functionality for leaving feedback.

        # render: ->
        #     console.log 'details render'
        #     console.log 'container children', $('#navigation-contents').children()

        #     template_string = jade.template @template, @serializeData()
        #     #template_string = @getTemplate @serializeData()

        #     $container = $('#navigation-contents')
        #     console.log 'container children', $container.children()
        #     console.log $container.children(), $container.children().length

        #     # This does not work. The container is already empty at this point.
        #     $old_content = $container.children().first()

        #     $new_content = $(template_string)

        #     # TODO: Check that there is old content.

        #     # Add content with animation
        #     animations.render($container, @$old_content, $new_content, 'left')

        render_events: (events) ->
            if events?
                @events_region.show new EventListView
                    collection: events

        show_more_events: (event) ->
            event.preventDefault()
            options =
                spinner_options:
                    container: @$('.show-more-events').get(0)
                    hide_container_content: true
            if @model.event_list.length <= @INITIAL_NUMBER_OF_EVENTS
                @model.get_events({}, options)
            else
                options.success = =>
                    @update_events_ui(@model.event_list.fetchState)
                @model.event_list.fetchNext(options)

        show_route_summary: (route) ->
            if route?
                @routing_region.show new RoutingSummaryView
                    model: route
                    to_address: @model.get 'street_address'

        request_route: (start) ->
            if @route?
                @route.clear_itinerary window.debug_map
            if not @model.get 'location'
                return

            if not @route?
                @route = new transit.Route()
                @listenTo @route, 'plan', (plan) =>
                    @route.draw_itinerary window.debug_map
                    @show_route_summary @route

            coords = @model.get('location').coordinates
            # railway station '60.171944,24.941389'
            # satamatalo 'osm:node:347379939'
            from = "#{start.latitude},#{start.longitude}"
            @route.plan from, "poi:tprek:#{@model.get 'id'}"

        onClose: ->
            if @route?
                @route.clear_itinerary window.debug_map

    class ServiceTreeView extends SMLayout
        id:
            'service-tree-container'
        template: 'service-tree'
        events:
            'click .service.has-children': 'open_service'
            'click .service.parent': 'open_service'
            'click .crumb': 'handle_breadcrumb_click'
            'click .service.leaf': 'toggle_leaf'
            'click .service .show-button': 'toggle_button'
            'click .service .show-icon': 'toggle_button'
        type: 'service-tree'

        initialize: (options) ->
            @selected_services = options.selected_services
            @breadcrumbs = options.breadcrumbs
            @animation_type = 'left'
            @scrollPosition = 0
            #@listenTo @collection, 'sync', @render
            # callback =  ->
            #     @preventAnimation = true
            #     @render()
            #     @preventAnimation = false
            @listenTo @selected_services, 'remove', @render
            @listenTo @selected_services, 'add', @render
            @listenTo @selected_services, 'reset', @render

        toggle_leaf: (event) ->
            @toggle_element($(event.currentTarget).find('.show-icon'))

        toggle_button: (event) ->
            event.preventDefault()
            event.stopPropagation()
            @toggle_element($(event.target))

        get_show_icon_classes: (showing, root_id) ->
            if showing
                return "show-icon selected service-color-#{root_id}"
            else
                return "show-icon service-hover-color-#{root_id}"

        toggle_element: ($target_element) ->
            service_id = $target_element.closest('li').data('service-id')
            unless @selected(service_id) is true
                service = new models.Service id: service_id
                service.fetch
                    success: =>
                        app.commands.execute 'addService', service
            else
                app.commands.execute 'removeService', service_id

        handle_breadcrumb_click: (event) ->
            event.preventDefault()
            # We need to stop the event from bubling to the containing element.
            # That would make the service tree go back only one step even if
            # user is clicking an earlier point in breadcrumbs.
            event.stopPropagation()
            @open_service(event)

        open_service: (event) ->
            $target = $(event.currentTarget)
            service_id = $target.data('service-id')
            service_name = $target.data('service-name')
            @animation_type = $target.data('slide-direction')
            console.log 'service tree open service', @animation_type

            if not service_id
                return null

            if service_id == 'root'
                service_id = null
                # Use splice to affect the original breadcrumbs array.
                @breadcrumbs.splice 0, @breadcrumbs.length
            else
                # See if the service is already in the breadcrumbs.
                index = _.indexOf(_.pluck(@breadcrumbs, 'service_id'), service_id)
                if index != -1
                    # Use splice to affect the original breadcrumbs array.
                    @breadcrumbs.splice index, @breadcrumbs.length - index
                @breadcrumbs.push(service_id: service_id, service_name: service_name)

            spinner_options =
                container: $target.get(0)
                hide_container_content: true
            @collection.expand service_id, spinner_options

        set_max_height: (height) =>
            if height?
                max_height = height
            else
                max_height = $(window).innerHeight() - @$el.offset().top
            @$el.find('.service-tree').css 'max-height': max_height

        set_breadcrumb_widths: ->
            CRUMB_MIN_WIDTH = 40
            # We need to use the last() jQuery method here, because at this
            # point the animations are still running and the DOM contains,
            # both the old and the new content. We only want to get the new
            # content and its breadcrumbs as a basis for our calculations.
            $container = @$el.find('.header-item').last()
            $crumbs = $container.find('.crumb')
            return unless $crumbs.length > 1

            # The last breadcrumb is given preference, so separate that from the
            # rest of the breadcrumbs.
            $last_crumb = $crumbs.last()
            $crumbs = $crumbs.not(':last')

            $chevrons = $container.find('.icon-icon-forward')
            space_available = $container.width() - ($chevrons.length * $chevrons.first().outerWidth())
            last_width = $last_crumb.width()
            space_needed = last_width + $crumbs.length * CRUMB_MIN_WIDTH

            if space_needed > space_available
                # Not enough space -> make the last breadcrumb narrower.
                last_width = space_available - $crumbs.length * CRUMB_MIN_WIDTH
                $last_crumb.css('max-width': last_width)
                $crumbs.css('max-width': CRUMB_MIN_WIDTH)
            else
                # More space -> Make the other breadcrumbs wider.
                crumb_width = (space_available - last_width) / $crumbs.length
                $crumbs.css('max-width': crumb_width)

        selected: (service_id) ->
            @selected_services.get(service_id)?
        close: ->
            @remove()
            @stopListening()

        serializeData: ->
            classes = (category) ->
                if category.get('children').length > 0
                    return ['service has-children']
                else
                    return ['service leaf']

            list_items = @collection.map (category) =>
                selected = @selected(category.id)

                root_id = category.get 'root'

                id: category.get 'id'
                name: category.get_text 'name'
                classes: classes(category).join " "
                has_children: category.attributes.children.length > 0
                selected: selected
                root_id: root_id
                show_icon_classes: @get_show_icon_classes selected, root_id

            parent_item = {}
            back = null

            if @collection.chosen_service
                back = @collection.chosen_service.get('parent') or 'root'
                parent_item.name = @collection.chosen_service.get_text 'name'
                parent_item.root_id = @collection.chosen_service.get 'root'

            data =
                back: back
                parent_item: parent_item
                list_items: list_items
                breadcrumbs: _.initial @breadcrumbs # everything but the last crumb

        # render: ->
        #     console.log 'service tree render'
        #     data = @serializeData()
        #     template_string = jade.template 'service-tree', data
        #     $old_content = @$el.find('ul')

        #     if !@preventAnimation and $old_content.length
        #         # Add content with animation
        #         animations.render(@$el, $old_content, $(template_string), @animation_type)
        #     else
        #         @el.innerHTML = template_string

        #     if @service_to_display
        #         $target_element = @$el.find("[data-service-id=#{@service_to_display.id}]").find('.show-icon')
        #         @service_to_display = false
        #         @toggle_element($target_element)

        #     $ul = @$el.find('ul')
        #     $ul.on('scroll', (ev) =>
        #         @scrollPosition = ev.currentTarget.scrollTop)
        #     $ul.scrollTop(@scrollPosition)
        #     @scrollPosition = 0
        #     @set_max_height()
        #     return @el

    class SearchResultView extends SMItemView
        tagName: 'li'
        events:
            'click': 'select_result'
            'mouseenter': 'highlight_result'
        template: 'search-result'
        select_result: (ev) ->
            if @model.get('object_type') == 'unit'
                app.commands.execute 'selectUnit', @model
            else if @model.get('object_type') == 'service'
                app.commands.execute 'addService', @model
        highlight_result: (ev) ->
            @model.marker?.openPopup()

    class SearchResultsView extends SMCollectionView
        tagName: 'ul'
        className: 'search-results'
        itemView: SearchResultView
        type: 'search'
        initialize: (opts) ->
            @parent = opts.parent
        onRender: ->
            @set_max_height()
        set_max_height: () =>
            max_height = $(window).innerHeight() - $('#navigation-contents').offset().top
            @$el.css 'max-height': max_height

    class ServiceCart extends SMItemView
        events:
            'click .button.close-button': 'close_service'
        initialize: (opts) ->
            @collection = opts.collection
            @listenTo @collection, 'add', @render
            @listenTo @collection, 'remove', @render
            @listenTo @collection, 'reset', @render
            @minimized = true
        close_service: (ev) ->
            app.commands.execute 'removeService', $(ev.currentTarget).data('service')
        attributes: ->
                class: if @minimized then 'minimized' else 'expanded'

        template: 'service-cart'
        tagName: 'ul'

    class LanguageSelectorView extends SMItemView
        template: 'language-selector'
        events:
            'click .language': 'select_language'
        initialize: (opts) ->
            @p13n = opts.p13n
            @languages = @p13n.get_supported_languages()
            @refresh_collection()
        select_language: (ev) ->
            l = $(ev.currentTarget).data('language')
            @p13n.set_language(l)
            window.location.reload()
        refresh_collection: ->
            selected = @p13n.get_language()
            language_models = _.map @languages, (l) ->
                new models.Language
                    code: l.code
                    name: l.name
                    selected: l.code == selected
            @collection = new models.LanguageList _.filter language_models, (l) -> !l.get('selected')

    class PersonalisationView extends SMItemView
        className: 'personalisation-container'
        template: 'personalisation'
        events:
            'click .personalisation-button': 'personalisation_button_click'
            'click .ok-button': 'toggle_menu'
            'click .select-on-map': 'select_on_map'
            'click .personalisations a': 'switch_personalisation'

        initialize: ->
            $(window).resize @set_max_height

        personalisation_button_click: (ev) ->
            ev.preventDefault()
            unless $('#personalisation').hasClass('open')
                @toggle_menu(ev)

        toggle_menu: (ev) ->
            ev.preventDefault()
            $('#personalisation').toggleClass('open')

        select_on_map: (ev) ->
            # Add here functionality for seleecting user's location from the map.
            ev.preventDefault()

        switch_personalisation: (ev) ->
            ev.preventDefault()
            parent_li = $(ev.target).closest 'li'
            group = parent_li.data 'group'
            type = parent_li.data 'type'

            mutex = false
            only_switch = false
            if group == 'senses'
            else if group == 'mobility'
                mutex = true
            else if group == 'transport'
                mutex = true
                only_switch = true
            else if group == 'city'
                mutex = true

            if parent_li.hasClass 'selected'
                # deactivate
                if only_switch
                    return
                parent_li.removeClass 'selected'
            else
                # activate
                if mutex
                    parent_li.parent().children().removeClass('selected')
                parent_li.addClass('selected')

        render: (opts) ->
            super opts
            defaults = # FIXME
                transport: 'public_transport'
                city: 'helsinki'
            for g of defaults
                el = @$el.find("li[data-group='#{g}'][data-type='#{defaults[g]}']")
                el.addClass 'selected'

        onRender: ->
            @set_max_height()

        set_max_height: =>
            # TODO: Refactor this when we get some onDomAppend event.
            # The onRender function that calls set_max_height runs before @el
            # is inserted into DOM. Hence calculating heights and positions of
            # the template elements is currently impossible.
            MOBILE_LAYOUT_BREAKPOINT = 480
            personalisation_header_height = 56
            window_width = $(window).width()
            offset = 0
            if window_width > MOBILE_LAYOUT_BREAKPOINT
                offset = $('#personalisation').offset().top
            max_height = $(window).innerHeight() - personalisation_header_height - offset
            @$el.find('.personalisation-content').css 'max-height': max_height

    exports =
        LandingTitleView: LandingTitleView
        TitleView: TitleView
        ServiceTreeView: ServiceTreeView
        ServiceCart: ServiceCart
        LanguageSelectorView: LanguageSelectorView
        NavigationLayout: NavigationLayout
        PersonalisationView: PersonalisationView

    return exports
