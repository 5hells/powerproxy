(ns powerschoolwrap
  (:gen-class)
  (:require [auth :as auth]
            [schedule :as schedule]
            [cheshire.core :as json]
            [compojure.core :refer [defroutes GET POST]]
            [compojure.route :as route]
            [ring.adapter.jetty :as jetty]
            [ring.middleware.params :refer [wrap-params]]
            [ring.util.response :as response]
            [hiccup.form :as form]
            [hiccup.page :as page]))

(defroutes app-routes
  (GET "/" []
    (page/html5
     [:head
      [:title "PowerSchoolWrap Test UI"]
      [:style "body { font-family: Arial, sans-serif; margin: 40px; }
               .form-group { margin-bottom: 15px; }
               label { display: block; margin-bottom: 5px; }
               input { width: 300px; padding: 8px; }
               button { padding: 10px 20px; background-color: #007bff; color: white; border: none; cursor: pointer; }
               button:hover { background-color: #0056b3; }
               .result { margin-top: 20px; padding: 10px; border: 1px solid #ccc; }
               .success { color: green; }
               .error { color: red; }"]]
     [:body
      [:h1 "PowerSchoolWrap Authentication Test"]
      (form/form-to [:post "/test-auth"]
                    [:div.form-group
                     (form/label "username" "Username:")
                     (form/text-field "username")]
                    [:div.form-group
                     (form/label "password" "Password:")
                     (form/password-field "password")]
                    [:div.form-group
                     (form/label "ps-base" "PS Base (e.g., yourschool):")
                     (form/text-field "ps-base")]
                    (form/submit-button "Test Authentication"))]))
  (POST "/test-auth" [username password ps-base]
    (let [result (try
                   (let [cookies (auth/authenticate-user username password ps-base)]
                     {:success true :cookies cookies})
                   (catch Exception e
                     {:success false :error (.getMessage e)}))]
      (page/html5
       [:head
        [:title "Test Result"]
        [:style "body { font-family: Arial, sans-serif; margin: 40px; }
                 .result { margin-top: 20px; padding: 10px; border: 1px solid #ccc; }
                 .success { color: green; }
                 .error { color: red; }"]]
       [:body
        [:h1 "Authentication Test Result"]
        [:div {:class (if (:success result) "result success" "result error")}
         (if (:success result)
           [:div
            [:p "Authentication successful!"]
            [:p "Cookies: " (pr-str (:cookies result))]
            [:h2 "Test Data Fetching"]
            (form/form-to [:post "/test-schedule"]
                          (form/hidden-field "cookies-json" (json/generate-string (:cookies result)))
                          (form/hidden-field "ps-base" ps-base)
                          (form/submit-button {:style "margin-right: 10px;"} "Test Schedule Fetch"))
            (form/form-to [:post "/test-grades"]
                          (form/hidden-field "cookies-json" (json/generate-string (:cookies result)))
                          (form/hidden-field "ps-base" ps-base)
                          (form/submit-button {:style "margin-right: 10px;"} "Test Grades Fetch"))
            (form/form-to [:post "/test-class-grades"]
                          (form/hidden-field "cookies-json" (json/generate-string (:cookies result)))
                          (form/hidden-field "ps-base" ps-base)
                          (form/submit-button "Test Class Grades Fetch"))]
           [:div
            [:p "Authentication failed: " (:error result)]])]
        [:p [:a {:href "/"} "Back to test form"]]])))
  (POST "/test-schedule" [cookies-json ps-base]
    (let [result (try
                   (let [schedule-data (schedule/fetch-schedule (json/parse-string cookies-json) ps-base)]
                     {:success true :data schedule-data})
                   (catch Exception e
                     {:success false :error (.getMessage e)}))]
      (page/html5
       [:head
        [:title "Schedule Test Result"]
        [:style "body { font-family: Arial, sans-serif; margin: 40px; }
                 .result { margin-top: 20px; padding: 10px; border: 1px solid #ccc; }
                 .success { color: green; }
                 .error { color: red; }
                 pre { white-space: pre-wrap; }"]]
       [:body
        [:h1 "Schedule Fetch Test Result"]
        [:div {:class (if (:success result) "result success" "result error")}
         (if (:success result)
           [:div
            [:p "Schedule fetched successfully!"]
            [:pre (pr-str (:data result))]]
           [:div
            [:p "Schedule fetch failed: " (:error result)]])]
        [:p [:a {:href "/"} "Back to test form"]]])))
  (POST "/test-grades" [cookies-json ps-base]
    (let [result (try
                   (let [grades-data (schedule/fetch-attendance-totals (json/parse-string cookies-json) ps-base)]
                     {:success true :data grades-data})
                   (catch Exception e
                     {:success false :error (.getMessage e)}))]
      (page/html5
       [:head
        [:title "Grades Test Result"]
        [:style "body { font-family: Arial, sans-serif; margin: 40px; }
                 .result { margin-top: 20px; padding: 10px; border: 1px solid #ccc; }
                 .success { color: green; }
                 .error { color: red; }
                 pre { white-space: pre-wrap; }"]]
       [:body
        [:h1 "Grades Fetch Test Result"]
        [:div {:class (if (:success result) "result success" "result error")}
         (if (:success result)
           [:div
            [:p "Grades fetched successfully!"]
            [:pre (pr-str (:data result))]]
           [:div
            [:p "Grades fetch failed: " (:error result)]])]
        [:p [:a {:href "/"} "Back to test form"]]])))
  (POST "/test-class-grades" [cookies-json ps-base]
    (let [result (try
                   (let [class-grades-data (schedule/fetch-class-grades (json/parse-string cookies-json) ps-base)]
                     {:success true :data class-grades-data})
                   (catch Exception e
                     {:success false :error (.getMessage e)}))]
      (page/html5
       [:head
        [:title "Class Grades Test Result"]
        [:style "body { font-family: Arial, sans-serif; margin: 40px; }
                 .result { margin-top: 20px; padding: 10px; border: 1px solid #ccc; }
                 .success { color: green; }
                 .error { color: red; }
                 pre { white-space: pre-wrap; }"]]
       [:body
        [:h1 "Class Grades Fetch Test Result"]
        [:div {:class (if (:success result) "result success" "result error")}
         (if (:success result)
           [:div
            [:p "Class grades fetched successfully!"]
            [:pre (pr-str (:data result))]]
           [:div
            [:p "Class grades fetch failed: " (:error result)]])]
        [:p [:a {:href "/"} "Back to test form"]]])))
  (POST "/authenticate" [username password ps-base]
    (try
      (let [cookies (auth/authenticate-user username password ps-base)]
        (response/response (json/generate-string cookies)))
      (catch Exception e
        (let [msg (.getMessage e)]
          (if (clojure.string/includes? msg "Invalid username or password")
            (response/status 401 (json/generate-string {:error "Invalid username or password"}))
            (response/status 500 (json/generate-string {:error msg})))))))
  (POST "/schedule" [cookies-json ps-base]
    (let [cookies (json/parse-string cookies-json)
          schedule-data (schedule/fetch-schedule cookies ps-base)]
      (response/response (json/generate-string schedule-data))))
  (POST "/grades" [cookies-json ps-base]
    (let [cookies (json/parse-string cookies-json)
          grades-data (schedule/fetch-attendance-totals cookies ps-base)]
      (response/response (json/generate-string grades-data))))
  (POST "/class-grades" [cookies-json ps-base]
    (let [cookies (json/parse-string cookies-json)
          class-grades-data (schedule/fetch-class-grades cookies ps-base)]
      (response/response (json/generate-string class-grades-data))))
  (route/not-found "Not Found"))

(defn -main
  "Main entry point for the PowerSchoolWrap server."
  [& args]
  (let [port (Integer/parseInt (or (first args) "3000"))]
    (println (str "Starting PowerSchoolWrap server on port " port))
    (jetty/run-jetty (wrap-params app-routes) {:port port :host "0.0.0.0"})))