import React, {useEffect} from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  TouchableOpacity,
  ScrollView,
  Image,
  ImageSourcePropType,
} from 'react-native';
import {StepIndicator} from './StepIndicator';
import {Colors} from '../utils/colors';
import {ScreenLogger} from '../utils/logger';
import {APP_VERSION, RN_SDK_VERSION} from '../config';
import type {Category, ProductCard} from '../types/models';

type ScreenContainerProps = {
  screenName: string;
  title: string;
  subtitle: string;
  step: number;
  icon: string;
  color: string;
  imageUrl?: string;
  logoSource?: ImageSourcePropType;
  onBack?: () => void;
  onCart?: () => void;
  children: React.ReactNode;
};

export const ScreenContainer: React.FC<ScreenContainerProps> = ({
  screenName,
  title,
  subtitle,
  step,
  icon,
  color,
  imageUrl,
  logoSource,
  onBack,
  onCart,
  children,
}) => {
  useEffect(() => {
    ScreenLogger.logScreenView(screenName);
  }, [screenName]);

  return (
    <SafeAreaView style={[styles.container, {backgroundColor: Colors.screen}]}>
      <View style={styles.content}>
        <View style={styles.headerRow}>
          <TouchableOpacity style={styles.headerAction} onPress={onBack} disabled={!onBack}>
            <Text style={[styles.headerActionText, !onBack && styles.hidden]}>‹</Text>
          </TouchableOpacity>
          <StepIndicator currentStep={step} activeColor={color} />
          <TouchableOpacity style={styles.headerAction} onPress={onCart} disabled={!onCart}>
            <Text style={[styles.headerActionText, !onCart && styles.hidden]}>🛒</Text>
          </TouchableOpacity>
        </View>

        {imageUrl ? (
          <Image source={{uri: imageUrl}} style={styles.productImage} resizeMode="cover" />
        ) : logoSource ? (
          <View style={styles.logoContainer}>
            <Image source={logoSource} style={styles.logoImage} resizeMode="contain" />
          </View>
        ) : (
          <View style={[styles.iconContainer, {backgroundColor: `${color}33`}]}>
            <Text style={styles.icon}>{icon}</Text>
          </View>
        )}

        <Text style={styles.title}>{title}</Text>
        <Text style={styles.subtitle}>{subtitle}</Text>
        {logoSource ? <Text style={styles.version}>SDK v{RN_SDK_VERSION}</Text> : null}
        <Text style={styles.version}>App v{APP_VERSION}</Text>

        <View style={styles.buttonsContainer}>{children}</View>
      </View>
    </SafeAreaView>
  );
};

type ProductRowProps = {
  products: ProductCard[];
  onPress: (productId: string) => void;
};

export const ProductRowList: React.FC<ProductRowProps> = ({products, onPress}) => {
  if (products.length === 0) {
    return null;
  }

  return (
    <ScrollView style={styles.listBox} contentContainerStyle={styles.listContent}>
      {products.map(product => (
        <TouchableOpacity
          key={product.id}
          style={styles.productRow}
          onPress={() => onPress(product.id)}
          activeOpacity={0.85}>
          <Image source={{uri: product.image_url}} style={styles.rowImage} />
          <View style={styles.rowTextWrap}>
            <Text style={styles.rowTitle} numberOfLines={1}>
              {product.name}
            </Text>
            <Text style={styles.rowSubtitle}>${product.price.toFixed(2)}</Text>
          </View>
          <Text style={styles.rowArrow}>›</Text>
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
};

type CategoryRowProps = {
  categories: Category[];
  onPress: (category: string) => void;
};

export const CategoryRowList: React.FC<CategoryRowProps> = ({categories, onPress}) => {
  if (categories.length === 0) {
    return null;
  }

  return (
    <ScrollView style={styles.listBox} contentContainerStyle={styles.listContent}>
      {categories.map(category => (
        <TouchableOpacity
          key={category.name}
          style={styles.productRow}
          onPress={() => onPress(category.name)}
          activeOpacity={0.85}>
          <View style={styles.categoryBubble}>
            <Text style={styles.categoryInitial}>{category.name.charAt(0)}</Text>
          </View>
          <View style={styles.rowTextWrap}>
            <Text style={styles.rowTitle} numberOfLines={1}>
              {category.name}
            </Text>
            <Text style={styles.rowSubtitle}>{category.product_count} items</Text>
          </View>
          <Text style={styles.rowArrow}>›</Text>
        </TouchableOpacity>
      ))}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    flex: 1,
    paddingHorizontal: 20,
    paddingTop: 8,
    paddingBottom: 18,
    alignItems: 'center',
  },
  headerRow: {
    width: '100%',
    marginTop: 6,
    marginBottom: 10,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerAction: {
    width: 38,
    height: 38,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.panelStrong,
  },
  headerActionText: {
    color: Colors.text,
    fontSize: 18,
    fontWeight: '700',
  },
  hidden: {
    opacity: 0,
  },
  iconContainer: {
    width: 100,
    height: 100,
    borderRadius: 50,
    justifyContent: 'center',
    alignItems: 'center',
    marginVertical: 14,
  },
  logoContainer: {
    paddingHorizontal: 24,
    paddingVertical: 18,
    backgroundColor: '#1A1A2E',
    borderRadius: 12,
    marginVertical: 14,
    alignItems: 'center',
  },
  logoImage: {
    width: 220,
    height: 56,
  },
  productImage: {
    width: 112,
    height: 112,
    borderRadius: 56,
    marginVertical: 10,
  },
  icon: {
    fontSize: 42,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: Colors.text,
    textAlign: 'center',
    marginBottom: 6,
  },
  subtitle: {
    fontSize: 15,
    color: Colors.textMuted,
    textAlign: 'center',
    marginBottom: 16,
    paddingHorizontal: 8,
  },
  version: {
    fontSize: 11,
    color: Colors.textMuted,
    textAlign: 'center',
    marginBottom: 12,
  },
  buttonsContainer: {
    width: '100%',
    marginTop: 'auto',
  },
  listBox: {
    width: '100%',
    maxHeight: 235,
    marginBottom: 10,
  },
  listContent: {
    gap: 8,
  },
  productRow: {
    backgroundColor: 'rgba(17,24,39,0.05)',
    borderWidth: 1,
    borderColor: Colors.panelBorder,
    borderRadius: 12,
    padding: 8,
    flexDirection: 'row',
    alignItems: 'center',
  },
  rowImage: {
    width: 56,
    height: 56,
    borderRadius: 8,
    backgroundColor: 'rgba(17,24,39,0.10)',
  },
  rowTextWrap: {
    flex: 1,
    marginHorizontal: 10,
  },
  rowTitle: {
    fontSize: 14,
    color: Colors.text,
    fontWeight: '700',
  },
  rowSubtitle: {
    fontSize: 12,
    color: Colors.textMuted,
    marginTop: 4,
  },
  rowArrow: {
    color: Colors.text,
    fontSize: 22,
    fontWeight: '300',
  },
  categoryBubble: {
    width: 56,
    height: 56,
    borderRadius: 28,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(17,24,39,0.10)',
  },
  categoryInitial: {
    color: Colors.text,
    fontSize: 20,
    fontWeight: '700',
  },
});
