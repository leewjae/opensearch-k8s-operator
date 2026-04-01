package reconcilers

import (
	"context"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	opensearchv1 "github.com/opensearch-project/opensearch-k8s-operator/opensearch-operator/api/v1"
	k8s "github.com/opensearch-project/opensearch-k8s-operator/opensearch-operator/mocks/github.com/opensearch-project/opensearch-k8s-operator/opensearch-operator/pkg/reconcilers/k8s"
	"github.com/opensearch-project/opensearch-k8s-operator/opensearch-operator/pkg/helpers"
	"github.com/opensearch-project/opensearch-k8s-operator/opensearch-operator/pkg/reconciler"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
)

func newClusterReconciler(client *k8s.MockK8sClient, instance *opensearchv1.OpenSearchCluster) *ClusterReconciler {
	reconcilerContext := NewReconcilerContext(&helpers.MockEventRecorder{}, instance, instance.Spec.NodePools)
	return &ClusterReconciler{
		client:            client,
		ctx:               context.Background(),
		recorder:          &record.FakeRecorder{},
		reconcilerContext: &reconcilerContext,
		instance:          instance,
	}
}

var _ = Describe("reconcileBootstrapPod", func() {

	Context("When reconciling the bootstrap pod", func() {
		It("Should create the pod using StateCreated when it does not exist", func() {
			instance := &opensearchv1.OpenSearchCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-cluster",
					Namespace: "test-namespace",
				},
				Spec: opensearchv1.ClusterSpec{
					General: opensearchv1.GeneralConfig{
						HttpPort:    9200,
						ServiceName: "test-cluster",
						Version:     "2.11.1",
					},
				},
			}
			desiredPod := &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-cluster-bootstrap-0",
					Namespace: "test-namespace",
				},
			}

			mockClient := k8s.NewMockK8sClient(GinkgoT())
			mockClient.On("ReconcileResource", desiredPod, reconciler.StateCreated).
				Return(&ctrl.Result{}, nil)

			r := newClusterReconciler(mockClient, instance)
			result, err := r.reconcileBootstrapPod(desiredPod)

			Expect(err).ToNot(HaveOccurred())
			Expect(result).ToNot(BeNil())
			mockClient.AssertExpectations(GinkgoT())
		})

		It("Should never attempt to update an existing pod with StatePresent", func() {
			instance := &opensearchv1.OpenSearchCluster{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-cluster",
					Namespace: "test-namespace",
				},
				Spec: opensearchv1.ClusterSpec{
					General: opensearchv1.GeneralConfig{
						HttpPort:    9200,
						ServiceName: "test-cluster",
						Version:     "2.11.1",
					},
				},
			}
			desiredPod := &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-cluster-bootstrap-0",
					Namespace: "test-namespace",
				},
			}

			mockClient := k8s.NewMockK8sClient(GinkgoT())
			// StateCreated is idempotent: if pod exists it does nothing, so no StatePresent call
			mockClient.On("ReconcileResource", desiredPod, reconciler.StateCreated).
				Return(&ctrl.Result{}, nil)

			r := newClusterReconciler(mockClient, instance)
			_, err := r.reconcileBootstrapPod(desiredPod)

			Expect(err).ToNot(HaveOccurred())
			mockClient.AssertNotCalled(GinkgoT(), "ReconcileResource", desiredPod, reconciler.StatePresent)
			mockClient.AssertExpectations(GinkgoT())
		})
	})
})
