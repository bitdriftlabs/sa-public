import type {NativeStackScreenProps} from '@react-navigation/native-stack';

export type RootStackParamList = {
  Welcome: undefined;
  Browse: undefined;
  Search: undefined;
  Featured: undefined;
  Categories: undefined;
  CategoryBrowse: {category: string};
  ProductDetail: {source: string; productId: string};
  Reviews: {source: string; productId: string};
  Cart: {productId?: string} | undefined;
  Wishlist: {productId?: string} | undefined;
  CheckoutGuest: {productId?: string} | undefined;
  CheckoutSignIn: {productId?: string} | undefined;
  PaymentCard: {checkoutSession?: string} | undefined;
  PaymentApplePay: {checkoutSession?: string} | undefined;
  PaymentPayPal: {checkoutSession?: string} | undefined;
  PaymentAndroidPay: {checkoutSession?: string} | undefined;
  PaymentFailed: {paymentMethod?: string} | undefined;
  Confirmation: {orderId?: string} | undefined;
  Advanced: undefined;
};

export type ScreenProps<T extends keyof RootStackParamList> =
  NativeStackScreenProps<RootStackParamList, T>;
