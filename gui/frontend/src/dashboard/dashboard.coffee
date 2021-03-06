angular.module "mindbenderApp.dashboard", [
    "ui.ace"
    'ui.bootstrap'
]

.service "Dashboard", ($rootScope, $location, $http) ->
    NUM_MOST_RECENT_SNAPSHOTS_TO_SHOW = 10

    class Dashboard
        constructor: ->
            console.log "Dashboard initializing"

            # prepare array of links for navbar
            $rootScope.navLinks = [
                { url: '#/snapshot-run', name: 'Run Snapshot', img: 'run.png' }
                { url: '#/report-templates/edit', name: 'Configure Templates', img: 'gear.png' }
                { url: '#/snapshot/', name: 'View Snapshots', img: 'report.png' }
                { url: '#/dashboard', name: 'Task', img: 'task.png' }
            ]
            do @updateNavLinkForSnapshots
            $rootScope.isNavLinkActive = (navLink) ->
                matchesLocation = ({url}) -> url is "##{$location.$$url}"
                (matchesLocation navLink) or
                    not (_.isEmpty navLink.links) and
                        (_.any navLink.links, matchesLocation)
            $rootScope.location = $location

        updateNavLinkForSnapshots: (snapshotParams) =>
            # query string to append
            qs =
                if _.isEmpty snapshotParams then ""
                else "?#{"#{encodeURIComponent k}=#{encodeURIComponent v}" for k,v of snapshotParams}"
            # how to populate snapshot links for navbar
            updateLinks = =>
                navLinkForSnapshots = _.find $rootScope.navLinks, name: "View Snapshots"
                navLinkForSnapshots.links =
                    for snapshotId in $rootScope.mostRecentSnapshots
                        # TODO use different style to indicate whether snapshotParams is applicable to this snapshot or not
                        { url: "#/snapshot/#{snapshotId}/#{qs}", name: snapshotId }
                if $rootScope.mostRecentSnapshots > NUM_MOST_RECENT_SNAPSHOTS_TO_SHOW
                    navLinkForSnapshots.links = [
                        navLinkForSnapshots.links...
                        { isDivider: yes }
                        { url: navLinkForSnapshots.url, name: "View All" }
                    ]
            # after getting the snapshots from backend
            if $rootScope.mostRecentSnapshots?
                do updateLinks
            else
                $rootScope.mostRecentSnapshots = []
                @getSnapshotList()
                    .success (snapshots) =>
                        $rootScope.mostRecentSnapshots = _.first snapshots, NUM_MOST_RECENT_SNAPSHOTS_TO_SHOW
                        do updateLinks

        getSnapshotList: =>
            $http.get "/api/snapshot"

        # TODO move some common parts to the Dashboard class

    # the singleton instance registered as an Angular service
    new Dashboard

.config ($routeProvider) ->
    $routeProvider.when "/dashboard",
        templateUrl: "dashboard/index.html"
        controller: "IndexCtrl"

    $routeProvider.when "/snapshot-run",
        templateUrl: "dashboard/snapshot-run.html"
        controller: "SnapshotRunCtrl"

    $routeProvider.when "/snapshot/",
        templateUrl: "dashboard/snapshot-list.html"
        controller: "SnapshotListCtrl"

    $routeProvider.when "/snapshot/:snapshotId/",
        templateUrl: "dashboard/snapshot-view-reports.html"
        controller: "SnapshotReportsCtrl",
        reloadOnSearch: false

    $routeProvider.when "/report-templates/edit",
        templateUrl: "dashboard/report-templates-editor.html"
        controller: "EditTemplatesCtrl",
        reloadOnSearch: false

.controller "IndexCtrl", ($scope, Dashboard) ->
    $scope.hideNav = true

.controller "SnapshotRunCtrl", ($scope, $http, Dashboard) ->
    $scope.title = "Run Snapshot"

    $scope.loadConfigs = (switchToConfig) ->
        $http.get "/api/snapshot-config/"
            .success (data, status, headers, config) -> 
                $scope.configs = data
                if switchToConfig
                    $scope.currentSnapshotConfig = switchToConfig
                else
                    $scope.currentSnapshotConfig = data[0]

    $scope.loadConfigs()

    $http.get "/api/report-templates/"
        .success (data, status, headers, config) -> 
            $scope.templates = data 

    $scope.$watch "currentSnapshotConfig", (newValue, oldValue) ->
        if newValue
            $http.get "/api/snapshot-config/" + newValue
                .success (data, status, headers, config) -> 
                    $scope.configTemplates = data
                    console.log($scope.configTemplates)

    $scope.addTemplate = () ->
        $scope.configTemplates.push({"reportTemplate":"", "params": {}})

    $scope.updateParams = (configTemplate) ->
        $http.get "/api/report-template/" + configTemplate.reportTemplate
            .success (data, status, headers, config) -> 
                for param in Object.keys(data.params)
                    data.params[param] = data.params[param]['defaultValue']

                configTemplate.params = data.params


    $scope.removeTemplate = (template_key) ->
        $scope.configTemplates.splice(template_key, 1)

    $scope.updateConfig = () ->
        $http.put("/api/snapshot-config/" + $scope.currentSnapshotConfig, $scope.configTemplates)
    
    $scope.deleteConfig = () ->
        $http.delete("/api/snapshot-config/" + $scope.currentSnapshotConfig)
        delete $scope.configs[$scope.currentSnapshotConfig]
        $scope.currentSnapshotConfig = ""

    $scope.copyConfig = () ->
        $http.put("/api/snapshot-config/" + $scope.copySnapshotName, $scope.configTemplates)
            .success (data, status, headers, config) ->
                $scope.loadConfigs($scope.copySnapshotName)

    $scope.createConfig = () ->
        $http.put("/api/snapshot-config/" + $scope.newSnapshotName, "[]")
            .success (data, status, headers, config) ->
                $scope.loadConfigs($scope.newSnapshotName)
                $scope.newSnapshotName = ""

    $scope.runConfig = () ->
        $http.post("/api/snapshot", { snapshotConfig: $scope.currentSnapshotConfig })

.controller "SnapshotListCtrl", ($scope, $http, Dashboard) ->
    $scope.title = "View Snapshots"

    $http.get "/api/snapshot"
        .success (data, status, headers, config) -> 
            $scope.snapshots = data


.controller "SnapshotReportsCtrl", ($scope, $http, $routeParams, $location, $sce, Dashboard) ->
    $scope.title = "Snapshot " + $routeParams.snapshotId
    $scope.loading = false
    $scope.tabs = {
        table: { active: true }
        bar: { show: false }
        scatter: { show: false }
    }
    $scope.report = {}

    reportNotFound = (report_key) ->
        $scope.reportLoadError = "#{report_key} does not exist in snapshot #{$routeParams.snapshotId}"

    $scope.loadReportFromNav = (nav) ->
        if nav.$show || nav.$leaf
            $scope.loadReport(nav.$report_key)
        else
            nav.$show = true

    $scope.loadReport = (report_key) ->
        $scope.loading = true
        $scope.reportLoadError = null
        $location.search('report', report_key)
        reportIdFull = "#{$routeParams.snapshotId}/#{report_key}"

        # TODO check report_key from $scope.reports first

        $http.get "/api/snapshot/#{reportIdFull}"
            .success (result, status, headers, config) -> 
                $scope.loading = false
                $scope.currentReport = report_key

                if result[report_key]
                    result[report_key].html = $sce.trustAsHtml(result[report_key].html)
                else
                    return reportNotFound report_key

                $scope.report = result[report_key]

                for data_key of $scope.report.data
                    $scope.report.data[data_key].table = convertToRowOrder($scope.report.data[data_key].table)

                if $scope.report.html
                    $scope.report.isFormatted = false
                else
                    $scope.report.isFormatted = true
                    data_name = Object.keys($scope.report.data)[0]
                    $scope.report.formattedReport = $scope.report.data[data_name]
                    $scope.report.formattedReport.name = data_name

                    $scope.tabs.table.active = true

                    chart = $scope.report.formattedReport.chart
                    if chart
                        if $scope.tableHeaderIsNumeric($scope.report.formattedReport.table, chart.y)
                            $scope.tabs.bar.show = true

                            $scope.tabs.scatter.show = $scope.tableHeaderIsNumeric($scope.report.formattedReport.table, chart.x)
                        else
                            $scope.tabs.bar.show = false
                            $scope.tabs.scatter.show = false

                Dashboard.updateNavLinkForSnapshots $location.search()

            .error (data, status, headers, config) ->
                $scope.loading = false
                $scope.currentReport = report_key
                $scope.reportLoadError = status
                console.error "#{reportIdFull}: #{status} error while loading"

    loadReportAndUpdateSideNav = ->
        return unless $scope.reports?
        return if $scope.loading
        search_report = $location.search().report
        return unless search_report?
        if $scope.reports[search_report]?
            $scope.loadReport(search_report)
            search_report_split = $scope.convertReportKey(search_report)
            traverse_nav = $scope.nav
            for s in search_report_split
                traverse_nav[s]['$show'] = true
                traverse_nav = traverse_nav[s]
        else
            reportNotFound search_report

    do $scope.reloadSnapshot = ->
        $http.get "/api/snapshot/#{$routeParams.snapshotId}"
            .success (data, status, headers, config) -> 
                $scope.snapshot = data
                $scope.reports = data.reports
                $scope.sortReports(Object.keys(data.reports))
                loadReportAndUpdateSideNav()
                Dashboard.updateNavLinkForSnapshots()

    $scope.$watch (-> $location.search().report), (newValue, oldValue) ->
        loadReportAndUpdateSideNav()

    $scope.abortSnapshot = ->
        $http.delete "/api/snapshot/#{$routeParams.snapshotId}"
            .success -> $scope.reloadSnapshot()
            .error   -> $scope.reloadSnapshot()

    $scope.buildTree = (params, path_splits) ->
        result = {}

        for full_split in path_splits
            split = full_split[0]
            i = 0
            on_path = true
            for k in params
                if split[i] != k
                    on_path = false
                i += 1

            if on_path && split.length > i
                new_params = params.slice()
                new_params.push(split[i])
                children = $scope.buildTree(new_params, path_splits)
                result[split[i]] = children

                if Object.keys(children).length == 0
                    result[split[i]]['$leaf'] = true 

                tmp = full_split[1].split(" ")

                result[split[i]]['$report_key'] = tmp[0].split("/").slice(0, new_params.length).join("/") + " " + tmp[1]
                if i == 0
                    result[split[i]]['$show'] = true

        return result

    $scope.convertReportKey = (report_key) ->
        var_split = report_key.split(" ")
        path_split = var_split[0].split("/")
        path_split[0] += " (" + var_split[1] + ")"
        return path_split

    $scope.sortReports = (report_keys) ->
        path_splits = []
        
        for k in report_keys 
            path_splits.push([$scope.convertReportKey(k), k])

        $scope.nav = $scope.buildTree([], path_splits)


    $scope.tableHeaderIsNumeric = (table, header) ->
        for h in table.headers
            if h.name == header
                return h.isNumeric

        return false


    convertToRowOrder = (table) ->
        if !table.headers
            new_table = { headers: Object.keys(table), data: [] }

            for header in new_table.headers
                for k, v of table[header]
                    if !new_table.data[k]
                        new_table.data[k] = []

                    new_table.data[k].push(v)

            table = new_table

        for index, header of table.headers
            table.headers[index] = { name: header, isNumeric: true }

            for value, value_index in table.data[index]
                if value == ''
                    table.data[index][value_index] = null

                if isNaN(value)
                    table.headers[index].isNumeric = false

        return table


.controller "EditTemplatesCtrl", ($scope, $http, $location, Dashboard) ->
    $scope.title = "Configure Templates"

    $scope.loadTemplates = (switchToTemplate) ->
        $http.get "/api/report-templates/"
            .success (data, status, headers, config) -> 
                $scope.templateList = data
                if switchToTemplate
                    $location.search('template', switchToTemplate)
                else
                    $location.search('template', data[0])

    $scope.$watch (-> $location.search()['template']), (newValue) ->
        if newValue
            $scope.currentTemplateName = newValue
            $http.get "/api/report-template/" + $scope.currentTemplateName
                .success (data, status, headers, config) ->
                    $scope.template = $.extend({}, data);
                    $scope.template.params = []
                    for param in Object.keys(data.params)
                        $scope.template.params.push($.extend({ name: param }, data.params[param]))

                    if data.markdownTemplate
                        $scope.formatted = false
                    else
                        $scope.formatted = true

                    if data.chart
                        $scope.template.hasChart = true
                    else
                        $scope.template.hasChart = false

    $scope.loadTemplates()

    $scope.changeCurrentTemplate = () ->
        $location.search('template', $scope.currentTemplateName)

    $scope.addVariable = () ->
        $scope.template.params.push({})

    $scope.formatTemplateForUpdate = () ->
        params = {}
        
        for param in $scope.template.params
            params[param.name] = $.extend({}, param);
            delete params[param.name]['name']

        template = { params: params }
        if $scope.formatted
            template.sqlTemplate = $scope.template.sqlTemplate
        else
            template.markdownTemplate = $scope.template.markdownTemplate

        if $scope.template.hasChart
            template.chart = $scope.template.chart

        return template

    $scope.updateTemplate = () ->
        $scope.updateTemplateName($scope.currentTemplateName)

    $scope.updateTemplateName = (name, callback) ->
        template = $scope.formatTemplateForUpdate()
        $http.put("/api/report-template/" + name, template)
            .success (data, status, headers, config) ->
                if callback
                    callback()

    $scope.deleteTemplate = () ->
        $http.delete("/api/report-template/" + $scope.currentTemplateName)

    $scope.copyTemplate = () ->
        $scope.updateTemplateName($scope.copyTemplateName, ->
            $scope.loadTemplates($scope.copyTemplateName)
        )

    $scope.createTemplate = () ->
        $http.put("/api/report-template/" + $scope.newTemplateName, {params: {}, sqlTemplate: "" })
            .success (data, status, headers, config) ->
                $scope.loadTemplates($scope.newTemplateName)


.filter 'capitalize', () ->
    (input) ->
        input[0].toUpperCase() + input.substring(1)


.directive 'flash', ['$document', ($document) ->
    return {
        link: (scope, element, attr) ->
            element.on("click", (event) ->
                $('.flash').css('background-color', attr['flash'])
                setTimeout((-> $('.flash').css('background-color', '#FFF')), 1000)
            )
    }
]


.directive 'chart', ($timeout, $parse) ->
    return {
        template: '<div class="chart"></div><div class="slider"></div>',
        restrict: 'E',
        link: (scope, element, attrs) ->
           
            recursiveMerge = (obj1, obj2) ->
                for k of obj2
                    if typeof obj1[k] == 'object' && typeof obj2[k] == 'object'
                        obj1[k] = recursiveMerge(obj1[k], obj2[k])
                    else
                        obj1[k] = obj2[k]

                return obj1

            binData = (data, numBins) ->
                bucketSize = Math.ceil(data.length/numBins)
                labels = []
                buckets = []
                i = 0
                bucket = 0
                previousLabel = data[0][0]

                if bucketSize == 1
                    for point in data
                        buckets.push(point[1])
                        labels.push(point[0])
                else
                    for point in data
                        if i >= bucketSize
                            buckets.push(bucket)
                            labels.push("[" + previousLabel.toLocaleString() + ", " + point[0].toLocaleString() + ")")
                            previousLabel = point[0]
                            bucket = 0
                            i = 0
                        bucket += point[1]
                        i++

                    if bucket > 0
                        buckets.push(bucket)
                        labels.push("[" + previousLabel.toLocaleString() + ", " + point[0].toLocaleString() + "]")

                return { buckets: buckets, labels: labels }

            options = {
                chart: {},
                title: {
                    text: '',
                },
                xAxis: {
                    title: {
                        text: attrs.label
                    }
                }
            }

            # Get user data
            if attrs.data
                full_data = attrs.data
            else
                full_data = scope.report.data[attrs.file].table
            
            # Set chart-specific options
            if attrs.type == 'bar'
                options.chart.type = 'column'

            if attrs.type == 'scatter'
                options.chart.type = 'scatter'

            # Apply custom user options
            if attrs.highchartsOptions
               options = recursiveMerge(options, $parse(attrs.highchartsOptions)(scope, {}))

            if !options.series
                options.series = []

            # Format data
            xIndex = 0
            yIndex = 0
            for index, header of full_data.headers
                if attrs.axis == header.name
                    xIndex = index
                if attrs.yAxis == header.name
                    yIndex = index

            data = []
            for point in full_data.data
                data.push([point[xIndex], point[yIndex]])

            formatChartData = (data, xIsNumeric, numBins) ->
                if (numBins != 'undefined' && numBins < data.length) || (xIsNumeric && data.length > 3 ** 3)
                    if !numBins
                        numBins = Math.floor(Math.sqrt(data.length, 1/3))

                    bins = binData(data, numBins)

                    return {
                        xAxis: { categories: bins.labels },
                        series: {
                            name: attrs.yLabel,
                            data: bins.buckets
                        },
                        numBins: numBins
                    }
                else
                    return {
                        xAxis: {},
                        series: {
                            name: attrs.yLabel,
                            data: data
                        },
                        numBins: data.length
                    }

            # Format bar
            if attrs.type == 'bar'
                chartData = formatChartData(data, scope.tableHeaderIsNumeric(full_data, attrs.axis))
                options.series.push(chartData.series)
                options.xAxis.categories = chartData.xAxis.categories

            # Format scatter
            if attrs.type == 'scatter'
                options.series.push({
                    name: attrs.yLabel
                    data: data
                })

            # Render chart and slider
            $timeout ->
                element.find('.chart').highcharts(options)
            
                if attrs.type == 'bar' && scope.tableHeaderIsNumeric(full_data, attrs.axis)
                    element.find('.slider').slider({
                        min: 1,
                        max: data.length,
                        value: chartData.numBins,
                        slide: (event, ui) ->
                            chartData = formatChartData(data, scope.tableHeaderIsNumeric(full_data, attrs.axis), ui.value)
                            options.series[options.series.length - 1] = chartData.series
                            options.xAxis.categories = chartData.xAxis.categories

                            element.find('.chart').highcharts(options)
                    })
    }

.directive 'compileHtml', ['$compile', ($compile) ->
    return (scope, element, attrs) ->

        scope.$watch(
            (scope) -> return scope.$eval(attrs.compileHtml),
            (value) -> 
                if value
                    element.html(value.toString())
                    $compile(element.contents())(scope)
        )
]

