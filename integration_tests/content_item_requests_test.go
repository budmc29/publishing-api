package integration

import (
	"net/http"
	"net/http/httptest"

	. "github.com/alphagov/publishing-api"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/ghttp"
)

var _ = Describe("Content Item Requests", func() {
	var (
		contentItemJSON = `{
      "base_path": "/vat-rates",
      "title": "VAT Rates",
      "description": "VAT rates for goods and services",
      "format": "guide",
      "publishing_app": "mainstream_publisher",
      "locale": "en",
      "details": {
        "app": "or format",
        "specific": "data..."
      }
    }`
		contentItemPayload = []byte(contentItemJSON)
		urlArbiterResponse = `{"path":"/vat-rates","publishing_app":"mainstream_publisher"}`

		testPublishingAPI                *httptest.Server
		testURLArbiter, testContentStore *ghttp.Server

		urlArbiterResponseCode, contentStoreResponseCode           int
		urlArbiterResponseBody, contentStoreResponseBody, endpoint string

		expectedResponse HTTPTestResponse
	)

	BeforeEach(func() {
		TestRequestOrderTracker = make(chan TestRequestLabel, 2)

		testURLArbiter = ghttp.NewServer()
		testURLArbiter.AppendHandlers(ghttp.CombineHandlers(
			trackRequest(URLArbiterRequestLabel),
			ghttp.VerifyRequest("PUT", "/paths/vat-rates"),
			ghttp.VerifyJSON(`{"publishing_app": "mainstream_publisher"}`),
			ghttp.RespondWithPtr(&urlArbiterResponseCode, &urlArbiterResponseBody),
		))

		testContentStore = ghttp.NewServer()
		testContentStore.AppendHandlers(ghttp.CombineHandlers(
			trackRequest(ContentStoreRequestLabel),
			ghttp.VerifyRequest("PUT", "/content/vat-rates"),
			ghttp.VerifyJSON(contentItemJSON),
			ghttp.RespondWithPtr(&contentStoreResponseCode, &contentStoreResponseBody),
		))

		testPublishingAPI = httptest.NewServer(BuildHTTPMux(testURLArbiter.URL(), testContentStore.URL()))
		endpoint = testPublishingAPI.URL + "/content/vat-rates"
	})

	AfterEach(func() {
		testURLArbiter.Close()
		testContentStore.Close()
		testPublishingAPI.Close()
		close(TestRequestOrderTracker)
	})

	Describe("PUT /content", func() {
		Context("when URL arbiter errs", func() {
			It("returns a 422 status with the original response", func() {
				urlArbiterResponseCode = 422
				urlArbiterResponseBody = `{"path":"/vat-rates","publishing_app":"mainstream_publisher","errors":{"base_path":["is not valid"]}}`

				actualResponse := doRequest("PUT", endpoint, contentItemPayload)

				Expect(testURLArbiter.ReceivedRequests()).Should(HaveLen(1))
				Expect(testContentStore.ReceivedRequests()).Should(BeEmpty())

				expectedResponse = HTTPTestResponse{Code: 422, Body: urlArbiterResponseBody}
				assertSameResponse(actualResponse, &expectedResponse)
			})

			It("returns a 409 status with the original response", func() {
				urlArbiterResponseCode = 409
				urlArbiterResponseBody = `{"path":"/vat-rates","publishing_app":"mainstream_publisher","errors":{"base_path":["is already taken"]}}`

				actualResponse := doRequest("PUT", endpoint, contentItemPayload)

				Expect(testURLArbiter.ReceivedRequests()).Should(HaveLen(1))
				Expect(testContentStore.ReceivedRequests()).Should(BeEmpty())

				expectedResponse = HTTPTestResponse{Code: 409, Body: urlArbiterResponseBody}
				assertSameResponse(actualResponse, &expectedResponse)
			})
		})

		It("registers a path with URL arbiter and then publishes the content to the content store", func() {
			urlArbiterResponseCode, urlArbiterResponseBody = http.StatusOK, urlArbiterResponse
			contentStoreResponseCode, contentStoreResponseBody = http.StatusOK, contentItemJSON

			actualResponse := doRequest("PUT", endpoint, contentItemPayload)

			Expect(testURLArbiter.ReceivedRequests()).Should(HaveLen(1))
			Expect(testContentStore.ReceivedRequests()).Should(HaveLen(1))

			expectedResponse = HTTPTestResponse{Code: http.StatusOK, Body: contentItemJSON}
			assertPathIsRegisteredAndContentStoreResponseIsReturned(actualResponse, &expectedResponse)
		})

		It("returns a 400 error if given invalid JSON", func() {
			actualResponse := doRequest("PUT", endpoint, []byte("i'm not json"))

			Expect(testURLArbiter.ReceivedRequests()).Should(BeZero())
			Expect(testContentStore.ReceivedRequests()).Should(BeZero())

			expectedResponse = HTTPTestResponse{Code: http.StatusBadRequest}
			assertSameResponse(actualResponse, &expectedResponse)
		})
	})
})
